defmodule CrmReactorWeb.AdminLive.Users do
  use CrmReactorWeb, :live_view

  import CrmReactorWeb.AdminComponents
  import Ecto.Query

  alias CrmReactor.{Accounts, Repo}
  alias CrmReactor.Tenants.Tenant

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Users",
        tenants: [],
        users_without_telegram: [],
        filter_tenant: nil
      )
      |> stream(:users, [])

    if connected?(socket) do
      tenants = Repo.all(from(t in Tenant, select: t.tenant_id, order_by: t.tenant_id))
      users = Accounts.list_all_users()

      users_without_telegram =
        users
        |> Enum.filter(&is_nil(&1.telegram_id))
        |> Enum.map(&{&1.email, &1.tenant_id})

      {:ok,
       socket
       |> assign(tenants: tenants, users_without_telegram: users_without_telegram)
       |> stream(:users, users, reset: true)}
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

    <h2 style="margin-top:32px;font-size:1.1rem;font-weight:600;">Link Telegram</h2>
    <.admin_form id="link-telegram-form" phx_submit="link_telegram">
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">User</label>
        <select name="user_key" required style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
          <option value="">Select user...</option>
          <option :for={{email, tid} <- @users_without_telegram} value={"#{email}|#{tid}"}>
            <%= email %> (<%= tid %>)
          </option>
        </select>
      </div>
      <div>
        <label style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">Telegram ID</label>
        <input type="text" name="telegram_id" required placeholder="123456789" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;" />
      </div>
      <button type="submit" style="padding:8px 20px;background:#4f46e5;color:#fff;border:none;border-radius:6px;font-size:0.875rem;cursor:pointer;">Link</button>
    </.admin_form>

    <h2 style="margin-top:24px;font-size:1.1rem;font-weight:600;">All Users</h2>

    <form phx-change="filter" style="margin-bottom:16px;">
      <label style="font-size:0.8rem;font-weight:500;margin-right:8px;">Tenant</label>
      <select name="tenant" style="padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;">
        <option value="">All tenants</option>
        <option :for={tid <- @tenants} value={tid} selected={@filter_tenant == tid}><%= tid %></option>
      </select>
    </form>

    <.admin_table id="users" rows={@streams.users} cols={["Email", "Name", "Tenant", "Telegram", "Status", "Actions"]}>
      <:col :let={{_id, user}}>
        <td style="padding:10px 16px;font-size:0.875rem;font-weight:500;"><%= user.email %></td>
        <td style="padding:10px 16px;font-size:0.875rem;"><%= user.name || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;font-family:monospace;"><%= user.tenant_id %></td>
        <td style="padding:10px 16px;font-size:0.875rem;font-family:monospace;"><%= user.telegram_id || "-" %></td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <%= status_badge(user) %>
        </td>
        <td style="padding:10px 16px;font-size:0.875rem;">
          <div style="display:flex;gap:8px;flex-wrap:wrap;">
            <%= if user.has_account do %>
              <button phx-click="reset_password" phx-value-id={user.account_id} style="padding:4px 10px;background:#f59e0b;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;">
                Reset password
              </button>
            <% else %>
              <button phx-click="link_webapp" phx-value-id={user.id} style="padding:4px 10px;background:#4f46e5;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;">
                Link Webapp
              </button>
            <% end %>
            <%= if user.status == "suspended" do %>
              <button phx-click="reactivate" phx-value-id={user.id} style="padding:4px 10px;background:#16a34a;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;">
                Reactivate
              </button>
            <% else %>
              <button phx-click="suspend" phx-value-id={user.id} style="padding:4px 10px;background:#dc2626;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;" data-confirm="Suspend this user? They will lose access on all channels.">
                Suspend
              </button>
            <% end %>
            <button phx-click="delete_user" phx-value-id={user.id} style="padding:4px 10px;background:#7f1d1d;color:#fff;border:none;border-radius:4px;font-size:0.75rem;cursor:pointer;" data-confirm="Permanently delete this user? Their todos and expenses will be archived.">
              Delete
            </button>
          </div>
        </td>
      </:col>
    </.admin_table>
    """
  end

  defp status_badge(user) do
    case user.status do
      "suspended" ->
        Phoenix.HTML.raw(~s(<span style="color:#dc2626;font-weight:500;">Suspended</span>))

      "pending" ->
        if invite_expired?(user),
          do: Phoenix.HTML.raw(~s(<span style="color:#9ca3af;font-weight:500;">Expired</span>)),
          else: Phoenix.HTML.raw(~s(<span style="color:#f59e0b;">Pending invite</span>))

      _ ->
        channels =
          [
            if(user.has_account, do: "Web"),
            if(user.telegram_id, do: "Telegram")
          ]
          |> Enum.filter(& &1)
          |> Enum.join(" + ")

        suffix =
          if channels != "",
            do: " <span style=\"color:#999;font-size:0.75rem;\">(#{channels})</span>",
            else: ""

        Phoenix.HTML.raw("<span style=\"color:#16a34a;\">Active</span>" <> suffix)
    end
  end

  defp invite_expired?(%{has_account: true, confirmed_at: nil, account_created_at: created_at})
       when not is_nil(created_at) do
    DateTime.diff(DateTime.utc_now(), created_at, :hour) >= 24
  end

  defp invite_expired?(_), do: false

  # ── Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", %{"tenant" => tenant}, socket) do
    tenant = if tenant == "", do: nil, else: tenant
    users = Accounts.list_all_users(tenant)

    {:noreply,
     socket
     |> assign(filter_tenant: tenant)
     |> stream(:users, users, reset: true)}
  end

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
        {:noreply, reload_users(socket, "Account created for #{email}. Invite email sent.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_msg(changeset))}
    end
  end

  def handle_event("reset_password", %{"id" => id}, socket) do
    account = Accounts.get_account!(id)
    base_url = CrmReactorWeb.Endpoint.url()
    Accounts.deliver_password_reset_email(account, base_url)

    {:noreply, put_flash(socket, :info, "Password reset email sent to #{account.email}.")}
  end

  def handle_event("suspend", %{"id" => id}, socket) do
    mapping = Accounts.get_user_mapping!(id)

    case Accounts.suspend_user(mapping) do
      {:ok, _} ->
        {:noreply, reload_users(socket, "#{mapping.email} suspended.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to suspend user.")}
    end
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    mapping = Accounts.get_user_mapping!(id)

    case Accounts.reactivate_user(mapping) do
      {:ok, _} ->
        {:noreply, reload_users(socket, "#{mapping.email} reactivated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reactivate user.")}
    end
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    mapping = Accounts.get_user_mapping!(id)

    case Accounts.delete_user(mapping) do
      {:ok, _} ->
        {:noreply, reload_users(socket, "User #{mapping.email} deleted. Data archived.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user.")}
    end
  end

  def handle_event("link_webapp", %{"id" => id}, socket) do
    mapping = Accounts.get_user_mapping!(id)

    case Accounts.link_webapp(mapping, %{name: mapping.email}) do
      {:ok, account} ->
        base_url = CrmReactorWeb.Endpoint.url()
        Accounts.deliver_invite_email(account, base_url)
        {:noreply, reload_users(socket, "Webapp linked for #{mapping.email}. Invite sent.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_msg(changeset))}
    end
  end

  def handle_event("link_telegram", %{"user_key" => key, "telegram_id" => tg_id}, socket) do
    case String.split(key, "|", parts: 2) do
      [email, tid] ->
        case Accounts.link_telegram(email, tid, tg_id) do
          {:ok, _} ->
            {:noreply, reload_users(socket, "Telegram #{tg_id} linked to #{email}.")}

          {:error, :already_linked} ->
            {:noreply, put_flash(socket, :error, "#{email} already has a Telegram ID linked.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to link Telegram ID.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid user selection.")}
    end
  end

  defp reload_users(socket, flash_msg) do
    users = Accounts.list_all_users()

    users_without_telegram =
      users
      |> Enum.filter(&is_nil(&1.telegram_id))
      |> Enum.map(&{&1.email, &1.tenant_id})

    socket
    |> assign(users_without_telegram: users_without_telegram)
    |> stream(:users, users, reset: true)
    |> put_flash(:info, flash_msg)
  end

  defp changeset_error_msg(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
