defmodule CrmReactorWeb.BootstrapLive do
  use CrmReactorWeb, :live_view

  import Ecto.Query

  alias CrmReactor.Accounts
  alias CrmReactor.Accounts.Account
  alias CrmReactor.Repo

  def mount(params, _session, socket) do
    bootstrap_token = Application.get_env(:crm_reactor, :bootstrap_token)
    provided_token = params["token"]
    admin_count = Repo.aggregate(from(a in Account, where: a.role == "admin"), :count)

    cond do
      admin_count > 0 ->
        {:ok, socket |> put_flash(:error, "Setup already completed.") |> assign(allowed: false),
         layout: false}

      is_nil(bootstrap_token) ->
        {:ok, socket |> put_flash(:error, "Bootstrap not configured.") |> assign(allowed: false),
         layout: false}

      provided_token != bootstrap_token ->
        {:ok, socket |> put_flash(:error, "Invalid token.") |> assign(allowed: false),
         layout: false}

      true ->
        {:ok,
         socket
         |> assign(allowed: true)
         |> assign(form: to_form(%{"email" => "", "password" => ""}, as: :admin))
         |> assign(trigger_submit: false), layout: false}
    end
  end

  def handle_event("validate", %{"admin" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :admin))}
  end

  def handle_event("submit", %{"admin" => %{"email" => email, "password" => password}}, socket) do
    case Accounts.create_admin_account(%{email: email, password: password}) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin account created. You can now log in.")
         |> redirect(to: "/login")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

        {:noreply,
         socket
         |> put_flash(:error, "Failed: #{errors}")
         |> assign(form: to_form(%{"email" => email, "password" => ""}, as: :admin))}
    end
  end

  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; display: flex; align-items: center; justify-content: center; background: #f3f4f6;">
      <div style="width: 100%; max-width: 400px; padding: 32px; background: #fff; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
        <h1 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 24px; text-align: center; color: #2563eb;">
          Initial Setup
        </h1>

        <%= if msg = Phoenix.Flash.get(@flash, :error) do %>
          <p style="color: #dc2626; margin-bottom: 12px; font-size: 0.9rem;"><%= msg %></p>
        <% end %>

        <%= if msg = Phoenix.Flash.get(@flash, :info) do %>
          <p style="color: #16a34a; margin-bottom: 12px; font-size: 0.9rem;"><%= msg %></p>
        <% end %>

        <%= if @allowed do %>
          <p style="color: #6b7280; margin-bottom: 16px; font-size: 0.9rem;">
            Create the first admin account for CRM Reactor.
          </p>

          <form
            id="bootstrap-form"
            phx-submit="submit"
            phx-change="validate"
            style="display: flex; flex-direction: column; gap: 16px;"
          >
            <div>
              <label style="display: block; font-size: 0.85rem; font-weight: 500; margin-bottom: 4px;">
                Email
              </label>
              <input
                type="email"
                name="admin[email]"
                value={@form[:email].value}
                required
                autofocus
                style="width: 100%; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
              />
            </div>
            <div>
              <label style="display: block; font-size: 0.85rem; font-weight: 500; margin-bottom: 4px;">
                Password
              </label>
              <input
                type="password"
                name="admin[password]"
                value={@form[:password].value}
                required
                minlength="8"
                style="width: 100%; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
              />
            </div>
            <button
              type="submit"
              style="padding: 12px; background: #2563eb; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer; font-weight: 600;"
            >
              Create Admin Account
            </button>
          </form>
        <% else %>
          <p style="color: #6b7280; text-align: center;">This page is not available.</p>
        <% end %>
      </div>
    </div>
    """
  end
end
