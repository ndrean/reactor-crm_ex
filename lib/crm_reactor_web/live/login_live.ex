defmodule CrmReactorWeb.LoginLive do
  use CrmReactorWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(form: to_form(%{"email" => "", "password" => ""}, as: :account))
     |> assign(magic_link_form: to_form(%{"email" => ""}, as: :magic_link)), layout: false}
  end

  def handle_event("validate", %{"account" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :account))}
  end

  def handle_event("validate", %{"magic_link" => params}, socket) do
    {:noreply, assign(socket, magic_link_form: to_form(params, as: :magic_link))}
  end

  def handle_event("send_magic_link", %{"magic_link" => %{"email" => email}}, socket) do
    base_url = CrmReactorWeb.Endpoint.url()
    CrmReactor.Accounts.deliver_magic_link_email(email, base_url)

    {:noreply,
     socket
     |> put_flash(:info, "Si un compte existe pour cet email, un lien de connexion a été envoyé.")
     |> assign(magic_link_form: to_form(%{"email" => ""}, as: :magic_link))}
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
            <div style="position: relative;">
              <input
                id="login-password"
                type="password"
                name="account[password]"
                value={@form[:password].value}
                required
                style="width: 100%; padding: 10px 14px; padding-right: 44px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
              />
              <button
                type="button"
                onclick="var i=document.getElementById('login-password'),o=this.querySelector('#eye-open'),c=this.querySelector('#eye-closed');if(i.type==='password'){i.type='text';o.style.display='none';c.style.display='inline'}else{i.type='password';o.style.display='inline';c.style.display='none'}"
                style="position: absolute; right: 8px; top: 50%; transform: translateY(-50%); background: none; border: none; cursor: pointer; padding: 4px; color: #9ca3af;"
                aria-label="Afficher le mot de passe"
              >
                <svg id="eye-open" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                <svg id="eye-closed" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:none;"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
              </button>
            </div>
          </div>
          <button
            type="submit"
            style="padding: 12px; background: #2563eb; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer; font-weight: 600;"
          >
            Se connecter
          </button>
        </form>

        <div style="text-align: center; margin: 20px 0 12px; color: #9ca3af; font-size: 0.85rem;">
          — ou —
        </div>

        <%= if msg = Phoenix.Flash.get(@flash, :info) do %>
          <p style="color: #16a34a; margin-bottom: 12px; font-size: 0.9rem;"><%= msg %></p>
        <% end %>

        <form
          id="magic-link-form"
          phx-submit="send_magic_link"
          phx-change="validate"
          style="display: flex; flex-direction: column; gap: 12px;"
        >
          <div>
            <label style="display: block; font-size: 0.85rem; font-weight: 500; margin-bottom: 4px;">
              Email
            </label>
            <input
              type="email"
              name="magic_link[email]"
              value={@magic_link_form[:email].value}
              required
              style="width: 100%; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
            />
          </div>
          <button
            type="submit"
            style="padding: 12px; background: #fff; color: #2563eb; border: 2px solid #2563eb; border-radius: 8px; font-size: 1rem; cursor: pointer; font-weight: 600;"
          >
            Envoyer un lien de connexion
          </button>
        </form>
      </div>
    </div>
    """
  end
end
