defmodule CrmReactor.Accounts do
  @moduledoc "Context for account management: login, sessions, invites."

  import Ecto.Query

  alias CrmReactor.Repo
  alias CrmReactor.Accounts.{Account, AccountToken}
  alias CrmReactor.Tenants.{UserMapping, TenantCache}

  # ── Login ──────────────────────────────────────────────────────────────────

  def get_account_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    account = Repo.get_by(Account, email: email)

    if account && is_nil(account.suspended_at) && Account.valid_password?(account, password) do
      account
    end
  end

  # ── Session tokens ─────────────────────────────────────────────────────────

  def generate_account_session_token(account) do
    {token, token_struct} = AccountToken.build_session_token(account)
    Repo.insert!(token_struct)
    token
  end

  def get_account_by_session_token(token) do
    AccountToken.verify_session_token_query(token)
    |> Repo.one()
  end

  def delete_account_session_token(token) do
    from(t in AccountToken, where: t.token == ^token and t.context == "session")
    |> Repo.delete_all()

    :ok
  end

  # ── Cross-channel tenant validation ────────────────────────────────────────

  @doc """
  Checks whether `email` is already associated with a different tenant.
  Returns `:ok` or `{:error, existing_tenant_id}`.
  """
  def check_email_tenant_conflict(email, tenant_id) when is_binary(email) do
    account_conflict =
      from(a in Account,
        where: a.email == ^email and a.tenant_id != ^tenant_id,
        select: a.tenant_id,
        limit: 1
      )
      |> Repo.one()

    mapping_conflict =
      from(m in UserMapping,
        where: m.user_email == ^email and m.tenant_id != ^tenant_id,
        select: m.tenant_id,
        limit: 1
      )
      |> Repo.one()

    case account_conflict || mapping_conflict do
      nil -> :ok
      existing -> {:error, existing}
    end
  end

  def check_email_tenant_conflict(nil, _tenant_id), do: :ok

  # ── Account creation ───────────────────────────────────────────────────────

  def create_admin_account(attrs) do
    %Account{}
    |> Account.registration_changeset(Map.put(attrs, :role, "admin"))
    |> Repo.insert()
  end

  def create_user_account(attrs) do
    email = attrs[:email] || attrs["email"]
    tenant_id = attrs[:tenant_id] || attrs["tenant_id"]

    case check_email_tenant_conflict(email, tenant_id) do
      {:error, existing} ->
        {:error,
         %Ecto.Changeset{
           action: :insert,
           errors: [
             email:
               {"is already associated with tenant '#{existing}'", [validation: :tenant_conflict]}
           ],
           valid?: false
         }}

      :ok ->
        Repo.transaction(fn ->
          case %Account{} |> Account.invite_changeset(attrs) |> Repo.insert() do
            {:ok, account} ->
              %UserMapping{}
              |> UserMapping.changeset(%{
                user_identifier: account.email,
                tenant_id: account.tenant_id,
                user_email: account.email
              })
              |> Repo.insert!()

              TenantCache.reload()
              account

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  # ── Invite flow ────────────────────────────────────────────────────────────

  def deliver_invite_email(account, base_url) do
    {encoded_token, token_struct} = AccountToken.build_invite_token(account)
    Repo.insert!(token_struct)

    invite_url = "#{base_url}/invite/#{encoded_token}"

    email = CrmReactor.Emails.InviteEmail.build(account.email, account.name, invite_url)
    CrmReactor.Mailer.deliver(email)

    {:ok, encoded_token}
  end

  def accept_invite(token, password) do
    with {:ok, query} <- AccountToken.verify_invite_token_query(token),
         %Account{} = account <- Repo.one(query) do
      Repo.transaction(fn ->
        updated =
          account
          |> Account.password_changeset(%{password: password})
          |> Repo.update!()

        # Clean up all invite tokens for this account
        from(t in AccountToken,
          where: t.account_id == ^account.id and t.context == "invite"
        )
        |> Repo.delete_all()

        updated
      end)
      |> case do
        {:ok, account} -> {:ok, account}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :invalid_token}
    end
  end

  # ── Account management ────────────────────────────────────────────────────

  def suspend_account(%Account{} = account) do
    account
    |> Ecto.Changeset.change(suspended_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
    |> tap(fn
      {:ok, acct} ->
        from(t in AccountToken, where: t.account_id == ^acct.id and t.context == "session")
        |> Repo.delete_all()

      _ ->
        :ok
    end)
  end

  def reactivate_account(%Account{} = account) do
    account
    |> Ecto.Changeset.change(suspended_at: nil)
    |> Repo.update()
  end

  def deliver_password_reset_email(%Account{} = account, base_url) do
    {encoded_token, token_struct} = AccountToken.build_invite_token(account)
    Repo.insert!(token_struct)

    reset_url = "#{base_url}/invite/#{encoded_token}"

    email =
      CrmReactor.Emails.PasswordResetEmail.build(account.email, account.name, reset_url)

    CrmReactor.Mailer.deliver(email)

    {:ok, encoded_token}
  end

  # ── Queries ────────────────────────────────────────────────────────────────

  def get_account!(id), do: Repo.get!(Account, id)

  def list_user_accounts do
    from(a in Account, where: a.role == "user", order_by: [asc: a.email])
    |> Repo.all()
  end
end
