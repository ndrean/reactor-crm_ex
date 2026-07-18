defmodule CrmReactorWeb.AdminLive.Users do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.{Accounts, Repo}
  alias CrmReactor.Tenants.{Tenant, UserMapping}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Users", tenants: [])
      |> stream(:users, [])
      |> stream(:accounts, [])

    if connected?(socket) do
      accounts = Accounts.list_user_accounts()
      account_emails = Enum.map(accounts, & &1.email)

      users =
        from(u in UserMapping,
          where: u.email not in ^account_emails,
          order_by: [asc: u.tenant_id, asc: u.email]
        )
        |> Repo.all()

      tenants = Repo.all(from(t in Tenant, select: t.tenant_id, order_by: t.tenant_id))

      {:ok,
       socket
       |> assign(tenants: tenants)
       |> stream(:users, users, reset: true)
       |> stream(:accounts, accounts, reset: true)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <h1>Users</h1>

    <h2 style="margin-top:24px;font-size:1.1rem;font-weight:600;">Create User Account</h2>
    <.admin_form id="create-account-form" phx_submit="create_account">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Name</label>
        <input type="text" name="name" required placeholder="Jean Dupont" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Email</label>
        <input type="email" name="email" required placeholder="user@example.com" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Tenant</label>
        <select name="tenant_id" required style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">Select...</option>
          <option :for={tid <- @tenants} value={tid}><%= tid %></option>
        </select>
      </div>
      <button type="submit" style="padding:8px 20px;background:#4f46e5;color:#fff;border:none;border-radius:6px;font-size:0.875rem;cursor:pointer;">Create & Send Invite</button>
    </.admin_form>

    <h2 style="margin-top:24px;font-size:1.1rem;font-weight:600;">User Accounts</h2>
    <.admin_table id="accounts" rows={@streams.accounts} cols={["Email", "Name", "Tenant", "Status", "Actions"]}>
      <:col :let={{_id, acct}}>
        <td style="padding:10px 16px;font-size:0.875rem;font-weight:500;"><%= acct.email %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= acct.name || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;font-family:monospace;"><%= acct.tenant_id %></td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <%= cond do %>
            <% acct.suspended_at -> %>
              <span style="color:#dc2626;font-weight:500;">Suspended</span>
            <% acct.confirmed_at -> %>
              <span style="color:#16a34a;">Active</span>
            <% true -> %>
              Pending invite
          <% end %>
        </td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <div style="display:flex;gap:8px;">
            <button phx-click="reset_password" phx-value-id={acct.id} style="padding:4px 10px;background:#f59e0b;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;">
              Reset password
            </button>
            <%= if acct.suspended_at do %>
              <button phx-click="toggle_suspend" phx-value-id={acct.id} style="padding:4px 10px;background:#16a34a;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;">
                Reactivate
              </button>
              <button phx-click="delete_account" phx-value-id={acct.id} style="padding:4px 10px;background:#7f1d1d;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;" data-confirm="Permanently delete this account and its mapping? This cannot be undone.">
                Delete
              </button>
            <% else %>
              <button phx-click="toggle_suspend" phx-value-id={acct.id} style="padding:4px 10px;background:#dc2626;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;" data-confirm="Suspend this user? They will be logged out immediately.">
                Suspend
              </button>
            <% end %>
          </div>
        </td>
      </:col>
    </.admin_table>

    <h2 style="margin-top:32px;font-size:1.1rem;font-weight:600;">Telegram Linkages</h2>
    <.admin_form id="add-user-form" phx_submit="add_user">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Tenant</label>
        <select name="tenant_id" required style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">Select...</option>
          <option :for={tid <- @tenants} value={tid}><%= tid %></option>
        </select>
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Email</label>
        <input type="email" name="email" required placeholder="user@example.com" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Telegram ID</label>
        <input type="text" name="telegram_id" required placeholder="123456789" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <button type="submit" style="padding:8px 20px;background:#4f46e5;color:#fff;border:none;border-radius:6px;font-size:0.875rem;cursor:pointer;">Add User</button>
    </.admin_form>

    <.admin_table id="users" rows={@streams.users} cols={["ID", "Tenant", "Email", "Telegram ID", "Actions"]}>
      <:col :let={{_id, user}}>
        <td style="padding:10px 16px;font-size:0.875rem;color:#999;"><%= user.id %></td>
        <td style="padding:10px 16px;font-size:0.875rem;font-weight:500;"><%= user.tenant_id %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= user.email %></td>
        <td style="padding:10px 16px;font-size:0.875rem;font-family:monospace;"><%= user.telegram_id || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <button phx-click="remove_mapping" phx-value-id={user.id} style="padding:4px 10px;background:#dc2626;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;" data-confirm="Remove this mapping? The user will lose access.">
            Remove
          </button>
        </td>
      </:col>
    </.admin_table>
    """
  end

  @impl true
  def handle_event(
        "create_account",
        %{"email" => email, "name" => name, "tenant_id" => tid},
        socket
      ) do
    attrs = %{email: email, name: name, tenant_id: tid}

    case Accounts.create_user_account(attrs) do
      {:ok, account} ->
        base_url = CrmReactorWeb.Endpoint.url()
        Accounts.deliver_invite_email(account, base_url)

        {:noreply,
         socket
         |> stream_insert(:accounts, account)
         |> put_flash(:info, "Account created for #{email}. Invite email sent.")}

      {:error, changeset} ->
        msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("reset_password", %{"id" => id}, socket) do
    account = Accounts.get_account!(id)
    base_url = CrmReactorWeb.Endpoint.url()
    Accounts.deliver_password_reset_email(account, base_url)

    {:noreply, put_flash(socket, :info, "Password reset email sent to #{account.email}.")}
  end

  def handle_event("toggle_suspend", %{"id" => id}, socket) do
    account = Accounts.get_account!(id)

    {result, msg} =
      if account.suspended_at do
        {Accounts.reactivate_account(account), "#{account.email} reactivated."}
      else
        {Accounts.suspend_account(account), "#{account.email} suspended."}
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:accounts, updated)
         |> put_flash(:info, msg)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update account.")}
    end
  end

  def handle_event("delete_account", %{"id" => id}, socket) do
    account = Accounts.get_account!(id)

    case Accounts.delete_account(account) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:accounts, account)
         |> put_flash(:info, "Account #{account.email} deleted.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete account.")}
    end
  end

  @impl true
  def handle_event(
        "add_user",
        %{"tenant_id" => tid, "email" => email, "telegram_id" => tg_id},
        socket
      ) do
    case Accounts.check_email_tenant_conflict(email, tid) do
      {:error, existing} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{email} is already associated with tenant '#{existing}'. Cannot add to '#{tid}'."
         )}

      :ok ->
        insert_user_mapping(socket, tid, email, tg_id)
    end
  end

  def handle_event(
        "link_telegram",
        %{"email" => email, "tenant_id" => tid, "telegram_id" => tg_id},
        socket
      ) do
    case Accounts.link_telegram(email, tid, tg_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Telegram #{tg_id} linked to #{email}.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No mapping found for #{email} in #{tid}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to link Telegram ID.")}
    end
  end

  def handle_event("remove_mapping", %{"id" => id}, socket) do
    mapping = Accounts.delete_user_mapping!(id)

    {:noreply,
     socket
     |> stream_delete(:users, mapping)
     |> put_flash(:info, "Mapping for #{mapping.email} removed.")}
  end

  defp insert_user_mapping(socket, tid, email, telegram_id) do
    tg = if telegram_id != "", do: telegram_id

    case Repo.get_by(UserMapping, email: email) do
      %{tenant_id: ^tid} ->
        do_link_telegram(socket, email, tid, tg)

      %{tenant_id: other} ->
        {:noreply,
         put_flash(socket, :error, "#{email} is already associated with tenant '#{other}'.")}

      nil ->
        do_create_mapping(socket, tid, email, tg)
    end
  end

  defp do_link_telegram(socket, email, _tid, nil) do
    {:noreply, put_flash(socket, :error, "#{email} already has a Telegram ID linked.")}
  end

  defp do_link_telegram(socket, email, tid, tg) do
    case Accounts.link_telegram(email, tid, tg) do
      {:ok, user} ->
        {:noreply,
         socket
         |> stream_insert(:users, user)
         |> put_flash(:info, "Telegram #{tg} linked to #{email}")}

      {:error, :already_linked} ->
        {:noreply, put_flash(socket, :error, "#{email} already has a Telegram ID linked.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_msg(changeset))}
    end
  end

  defp do_create_mapping(socket, tid, email, tg) do
    case Accounts.create_user_mapping(%{tenant_id: tid, email: email, telegram_id: tg}) do
      {:ok, user} ->
        {:noreply,
         socket
         |> stream_insert(:users, user)
         |> put_flash(:info, "User #{email} added to #{tid}")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_msg(changeset))}
    end
  end

  defp changeset_error_msg(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
