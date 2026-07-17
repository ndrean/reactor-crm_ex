defmodule CrmReactor.Accounts do
  @moduledoc "Context for account management: login, sessions, invites."

  import Ecto.Query

  alias CrmReactor.Accounts.{Account, AccountToken}
  alias CrmReactor.Emails.{InviteEmail, MagicLinkEmail, PasswordResetEmail}
  alias CrmReactor.Mailer
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.{TenantCache, UserMapping}

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
        where: m.email == ^email and m.tenant_id != ^tenant_id,
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
        insert_user_with_mapping(attrs)
    end
  end

  # ── Invite flow ────────────────────────────────────────────────────────────

  def deliver_invite_email(account, base_url) do
    {encoded_token, token_struct} = AccountToken.build_invite_token(account)
    Repo.insert!(token_struct)

    invite_url = "#{base_url}/invite/#{encoded_token}"

    email = InviteEmail.build(account.email, account.name, invite_url)
    Mailer.deliver(email)

    {:ok, encoded_token}
  end

  def accept_invite(token, password) when is_binary(password) do
    accept_invite(token, %{password: password, password_confirmation: password})
  end

  def accept_invite(token, %{} = password_attrs) do
    with {:ok, query} <- AccountToken.verify_invite_token_query(token),
         %Account{} = account <- Repo.one(query),
         %{valid?: true} = changeset <- Account.password_changeset(account, password_attrs) do
      accept_invite_transaction(account, changeset)
    else
      %Ecto.Changeset{} = changeset -> {:error, %{changeset | action: :update}}
      _ -> {:error, :invalid_token}
    end
  end

  defp accept_invite_transaction(account, changeset) do
    Repo.transaction(fn ->
      updated = Repo.update!(changeset)

      from(t in AccountToken,
        where: t.account_id == ^account.id and t.context == "invite"
      )
      |> Repo.delete_all()

      updated
    end)
  end

  # ── Magic link login ──────────────────────────────────────────────────────

  def deliver_magic_link_email(email, base_url) when is_binary(email) do
    account =
      from(a in Account, where: a.email == ^email and is_nil(a.suspended_at))
      |> Repo.one()

    if account do
      {encoded_token, token_struct} = AccountToken.build_magic_link_token(account)
      Repo.insert!(token_struct)

      magic_link_url = "#{base_url}/login/magic/#{encoded_token}"
      email_msg = MagicLinkEmail.build(account.email, magic_link_url)
      Mailer.deliver(email_msg)
    end

    # Always return :ok to not leak account existence
    :ok
  end

  def login_by_magic_link(encoded_token) do
    with {:ok, query} <- AccountToken.verify_magic_link_token_query(encoded_token),
         %Account{} = account <- Repo.one(query) do
      # Delete all magic_link tokens for this account (single-use)
      from(t in AccountToken,
        where: t.account_id == ^account.id and t.context == "magic_link"
      )
      |> Repo.delete_all()

      {:ok, account}
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

  def delete_account(%Account{} = account) do
    Repo.transaction(fn ->
      # Delete all tokens (session, invite)
      from(t in AccountToken, where: t.account_id == ^account.id) |> Repo.delete_all()

      # Delete associated user mapping
      from(m in UserMapping,
        where: m.email == ^account.email and m.tenant_id == ^account.tenant_id
      )
      |> Repo.delete_all()

      Repo.delete!(account)
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def deliver_password_reset_email(%Account{} = account, base_url) do
    {encoded_token, token_struct} = AccountToken.build_invite_token(account)
    Repo.insert!(token_struct)

    reset_url = "#{base_url}/invite/#{encoded_token}"

    email = PasswordResetEmail.build(account.email, account.name, reset_url)
    Mailer.deliver(email)

    {:ok, encoded_token}
  end

  # ── Queries ────────────────────────────────────────────────────────────────

  def get_account!(id), do: Repo.get!(Account, id)

  def list_user_accounts do
    from(a in Account, where: a.role == "user", order_by: [asc: a.email])
    |> Repo.all()
  end

  @doc """
  Links a Telegram ID to an existing user mapping.
  Triggers a TenantCache reload on success.
  """
  def link_telegram(email, tenant_id, telegram_id) do
    case Repo.get_by(UserMapping, email: email, tenant_id: tenant_id) do
      nil ->
        {:error, :not_found}

      %{telegram_id: existing_tg} when not is_nil(existing_tg) ->
        {:error, :already_linked}

      mapping ->
        mapping
        |> UserMapping.changeset(%{telegram_id: telegram_id})
        |> Repo.update()
        |> tap(fn
          {:ok, _} -> TenantCache.reload()
          _ -> :ok
        end)
    end
  end

  def create_user_mapping(attrs) do
    %UserMapping{}
    |> UserMapping.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def delete_user_mapping!(id) do
    mapping = Repo.get!(UserMapping, id)
    Repo.delete!(mapping)
    TenantCache.reload()
    mapping
  end

  defp insert_user_with_mapping(attrs) do
    Repo.transaction(fn ->
      case %Account{} |> Account.invite_changeset(attrs) |> Repo.insert() do
        {:ok, account} ->
          ensure_user_mapping(account)
          account

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  defp ensure_user_mapping(%{tenant_id: tid} = account) do
    case Repo.get_by(UserMapping, email: account.email) do
      %{tenant_id: ^tid} ->
        :ok

      nil ->
        %UserMapping{}
        |> UserMapping.changeset(%{email: account.email, tenant_id: account.tenant_id})
        |> Repo.insert!()

      %{tenant_id: other} ->
        Repo.rollback({:tenant_conflict, other})
    end
  end
end
