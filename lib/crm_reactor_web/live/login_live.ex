defmodule CrmReactorWeb.LoginLive do
  use CrmReactorWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{"email" => "", "password" => ""}, as: :account)),
     layout: false}
  end

  def handle_event("validate", %{"account" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :account))}
  end

  def handle_event("login", %{"account" => %{"email" => email, "password" => password}}, socket) do
    if CrmReactor.Accounts.get_account_by_email_and_password(email, password) do
      {:noreply,
       socket
       |> assign(form: to_form(%{"email" => email, "password" => password}, as: :account))
       |> assign(:trigger_submit, true)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Email ou mot de passe invalide.")
       |> assign(form: to_form(%{"email" => email, "password" => ""}, as: :account))}
    end
  end

  def render(assigns) do
    assigns = assign_new(assigns, :trigger_submit, fn -> false end)

    ~H"""
    <div style="min-height: 100vh; display: flex; align-items: center; justify-content: center; background: #f3f4f6;">
      <div style="width: 100%; max-width: 400px; padding: 32px; background: #fff; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
        <h1 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 24px; text-align: center; color: #2563eb;">
          CRM Reactor
        </h1>

        <%= if msg = Phoenix.Flash.get(@flash, :error) do %>
          <p style="color: #dc2626; margin-bottom: 12px; font-size: 0.9rem;"><%= msg %></p>
        <% end %>

        <form
          id="login-form"
          phx-submit="login"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          action="/login"
          method="post"
          style="display: flex; flex-direction: column; gap: 16px;"
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <div>
            <label style="display: block; font-size: 0.85rem; font-weight: 500; margin-bottom: 4px;">
              Email
            </label>
            <input
              type="email"
              name="account[email]"
              value={@form[:email].value}
              required
              autofocus
              style="width: 100%; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
            />
          </div>
          <div>
            <label style="display: block; font-size: 0.85rem; font-weight: 500; margin-bottom: 4px;">
              Mot de passe
            </label>
            <input
              type="password"
              name="account[password]"
              value={@form[:password].value}
              required
              style="width: 100%; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
            />
          </div>
          <button
            type="submit"
            style="padding: 12px; background: #2563eb; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer; font-weight: 600;"
          >
            Se connecter
          </button>
        </form>
      </div>
    </div>
    """
  end
end
