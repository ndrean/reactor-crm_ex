defmodule CrmReactor.Accounts do
  @moduledoc "Context for account management: login, sessions, invites."

  require Logger

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

  # ── Calendar tokens ───────────────────────────────────────────────────────

  def generate_calendar_token(account) do
    {encoded_token, token_struct} = AccountToken.build_calendar_token(account)
    Repo.insert!(token_struct)
    {:ok, encoded_token}
  end

  def get_or_create_calendar_token(account) do
    existing =
      from(t in AccountToken,
        where: t.account_id == ^account.id and t.context == "calendar",
        order_by: [desc: t.inserted_at],
        limit: 1
      )
      |> Repo.one()

    if existing do
      {:ok, Base.url_encode64(existing.token, padding: false)}
    else
      generate_calendar_token(account)
    end
  end

  def get_account_by_calendar_token(encoded_token) do
    case AccountToken.verify_calendar_token_query(encoded_token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def revoke_calendar_token(account) do
    from(t in AccountToken,
      where: t.account_id == ^account.id and t.context == "calendar"
    )
    |> Repo.delete_all()

    :ok
  end

  # ── Onboard tokens ──────────────────────────────────────────────────────────

  def generate_onboard_token(account) do
    {encoded_token, token_struct} = AccountToken.build_onboard_token(account)

    case Repo.insert(token_struct) do
      {:ok, _} -> {:ok, encoded_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_account_by_onboard_token(encoded_token) do
    case AccountToken.verify_onboard_token_query(encoded_token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def delete_onboard_tokens(%Account{} = account) do
    from(t in AccountToken,
      where: t.account_id == ^account.id and t.context == "onboard"
    )
    |> Repo.delete_all()
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
    with {encoded_token, token_struct} <- AccountToken.build_invite_token(account),
         {:ok, _} <- Repo.insert(token_struct),
         {:ok, onboard_token} <- generate_onboard_token(account),
         {:ok, calendar_token} <- get_or_create_calendar_token(account) do
      invite_url = "#{base_url}/invite/#{encoded_token}"
      onboard_url = "#{base_url}/onboard/#{onboard_token}"
      calendar_url = "#{base_url}/cal/#{calendar_token}"

      email =
        InviteEmail.build(account.email, account.name, invite_url, calendar_url, onboard_url)

      case Mailer.deliver(email) do
        {:ok, _} ->
          Logger.info("Invite email sent from #{elem(email.from, 1)} to #{account.email}")

        {:error, reason} ->
          Logger.error("Failed to send invite email to #{account.email}: #{inspect(reason)}")
      end

      {:ok, encoded_token}
    end
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

      # Activate the user mapping
      case Repo.get_by(UserMapping, email: account.email, tenant_id: account.tenant_id) do
        nil -> :ok
        mapping -> mapping |> UserMapping.changeset(%{status: "active"}) |> Repo.update!()
      end

      updated
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
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
         %Account{suspended_at: nil} = account <- Repo.one(query) do
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

  # ── User management (operates on UserMapping) ────────────────────────────

  def suspend_user(%UserMapping{} = mapping) do
    Repo.transaction(fn ->
      updated = update_mapping_or_rollback!(mapping, %{status: "suspended"})
      suspend_linked_account(mapping.email, mapping.tenant_id)
      updated
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def reactivate_user(%UserMapping{} = mapping) do
    Repo.transaction(fn ->
      updated = update_mapping_or_rollback!(mapping, %{status: "active"})
      reactivate_linked_account(mapping.email, mapping.tenant_id)
      updated
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def delete_user(%UserMapping{} = mapping) do
    Repo.transaction(fn ->
      archive_user_data(mapping.email, "customer_#{mapping.tenant_id}")
      delete_linked_account(mapping.email, mapping.tenant_id)
      Repo.delete!(mapping)
    end)
    |> tap(fn
      {:ok, _} -> TenantCache.reload()
      _ -> :ok
    end)
  end

  def link_webapp(%UserMapping{} = mapping, attrs) do
    account_attrs = Map.merge(attrs, %{email: mapping.email, tenant_id: mapping.tenant_id})

    Repo.transaction(fn ->
      account = insert_or_rollback!(Account.invite_changeset(%Account{}, account_attrs))
      update_mapping_or_rollback!(mapping, %{status: "pending"})
      account
    end)
  end

  defp update_mapping_or_rollback!(mapping, attrs) do
    case mapping |> UserMapping.changeset(attrs) |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert_or_rollback!(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp suspend_linked_account(email, tenant_id) do
    case Repo.get_by(Account, email: email, tenant_id: tenant_id) do
      nil ->
        :ok

      account ->
        account
        |> Ecto.Changeset.change(suspended_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update!()

        from(t in AccountToken,
          where: t.account_id == ^account.id and t.context in ["session", "calendar"]
        )
        |> Repo.delete_all()
    end
  end

  defp reactivate_linked_account(email, tenant_id) do
    case Repo.get_by(Account, email: email, tenant_id: tenant_id) do
      nil -> :ok
      account -> account |> Ecto.Changeset.change(suspended_at: nil) |> Repo.update!()
    end
  end

  defp delete_linked_account(email, tenant_id) do
    case Repo.get_by(Account, email: email, tenant_id: tenant_id) do
      nil ->
        :ok

      account ->
        from(t in AccountToken, where: t.account_id == ^account.id) |> Repo.delete_all()
        Repo.delete!(account)
    end
  end

  defp archive_user_data(email, schema) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(t in CrmReactor.CRM.Todo,
      where: t.created_by == ^email and is_nil(t.archived_at)
    )
    |> Repo.update_all([set: [archived_at: now]], prefix: schema)

    from(e in CrmReactor.CRM.Expense,
      where: e.created_by == ^email and is_nil(e.archived_at)
    )
    |> Repo.update_all([set: [archived_at: now]], prefix: schema)
  end

  # Legacy functions kept for backward compat
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
      from(t in AccountToken, where: t.account_id == ^account.id) |> Repo.delete_all()

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
  def get_account_by_email(email), do: Repo.get_by(Account, email: email)
  def get_user_mapping!(id), do: Repo.get!(UserMapping, id)

  def list_all_users(tenant_filter \\ nil) do
    query =
      from(m in UserMapping,
        left_join: a in Account,
        on: a.email == m.email and a.tenant_id == m.tenant_id,
        order_by: [asc: m.tenant_id, asc: m.email],
        select: %{
          id: m.id,
          email: m.email,
          tenant_id: m.tenant_id,
          telegram_id: m.telegram_id,
          status: m.status,
          name: a.name,
          has_account: not is_nil(a.id),
          account_id: a.id,
          confirmed_at: a.confirmed_at,
          account_created_at: a.inserted_at
        }
      )

    query =
      if tenant_filter,
        do: where(query, [m], m.tenant_id == ^tenant_filter),
        else: query

    Repo.all(query)
  end

  def list_user_accounts do
    from(a in Account,
      where: a.role == "user",
      left_join: m in UserMapping,
      on: m.email == a.email and m.tenant_id == a.tenant_id,
      order_by: [asc: a.email],
      select_merge: %{telegram_id: m.telegram_id}
    )
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
        |> UserMapping.changeset(%{
          email: account.email,
          tenant_id: account.tenant_id,
          status: "pending"
        })
        |> Repo.insert!()

      %{tenant_id: other} ->
        Repo.rollback({:tenant_conflict, other})
    end
  end
end
