defmodule CrmReactorWeb.OnboardLive do
  use CrmReactorWeb, :live_view

  alias CrmReactor.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_account_by_onboard_token(token) do
      nil ->
        {:ok,
         socket
         |> assign(page_title: "Lien Telegram", account: nil, token: token)
         |> put_flash(:error, "Ce lien est invalide ou a expiré.")}

      account ->
        changeset = changeset(%{})

        {:ok,
         assign(socket,
           page_title: "Lier votre Telegram",
           account: account,
           token: token,
           form: to_form(changeset),
           linked: false
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"onboard" => params}, socket) do
    changeset = changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("submit", %{"onboard" => %{"chat_id" => chat_id}}, socket) do
    account = socket.assigns.account

    changeset = changeset(%{"chat_id" => chat_id})

    if changeset.valid? do
      case Accounts.link_telegram(account.email, account.tenant_id, chat_id) do
        {:ok, _} ->
          Accounts.delete_onboard_tokens(account)

          {:noreply,
           socket
           |> assign(linked: true)
           |> put_flash(:info, "Telegram lié avec succès !")}

        {:error, :already_linked} ->
          {:noreply, put_flash(socket, :info, "Votre Telegram est déjà lié.")}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "Compte introuvable.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Erreur lors de la liaison.")}
      end
    else
      {:noreply, assign(socket, form: to_form(%{changeset | action: :validate}))}
    end
  end

  defp changeset(params) do
    types = %{chat_id: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:chat_id])
    |> Ecto.Changeset.validate_format(:chat_id, ~r/^\d{6,12}$/,
      message: "doit être un identifiant numérique (6-12 chiffres)"
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width:400px;margin:60px auto;padding:24px;">
      <h1 style="font-size:1.5rem;margin-bottom:8px;">Lier votre Telegram</h1>

      <%= if msg = Phoenix.Flash.get(@flash, :error) do %>
        <p style="color:#dc2626;margin-bottom:12px;font-size:0.875rem;"><%= msg %></p>
      <% end %>
      <%= if msg = Phoenix.Flash.get(@flash, :info) do %>
        <p style="color:#166534;margin-bottom:12px;font-size:0.875rem;"><%= msg %></p>
      <% end %>

      <%= if is_nil(@account) do %>
        <p style="color:#666;">Ce lien d'onboarding est invalide ou a expiré.</p>
      <% else %>
        <%= if @linked do %>
          <div style="background:#f0fdf4;padding:16px;border-radius:8px;border:1px solid #bbf7d0;">
            <p style="color:#166534;font-weight:500;">Votre Telegram a été lié avec succès.</p>
            <p style="color:#666;font-size:0.875rem;margin-top:8px;">
              Vous recevrez désormais vos notifications de calendrier via Telegram.
            </p>
          </div>
        <% else %>
          <p style="color:#666;margin-bottom:16px;font-size:0.9rem;">
            Pour recevoir vos rappels par Telegram, entrez votre chat ID ci-dessous.
            <br/><br/>
            <strong>Comment obtenir votre chat ID :</strong><br/>
            Envoyez <code>/start</code> au bot <a href="https://t.me/GetMyIDBot" target="_blank" style="color:#4f46e5;">@GetMyIDBot</a>
            sur Telegram. Il vous répondra avec votre identifiant numérique.
          </p>

          <.form for={@form} phx-change="validate" phx-submit="submit" id="onboard-form">
            <div style="margin-bottom:16px;">
              <label for="onboard_chat_id" style="display:block;font-size:0.8rem;font-weight:500;margin-bottom:4px;">
                Chat ID Telegram
              </label>
              <input
                type="text"
                id="onboard_chat_id"
                name="onboard[chat_id]"
                value={@form[:chat_id].value}
                placeholder="123456789"
                inputmode="numeric"
                required
                style="width:100%;padding:8px 12px;border:1px solid #ddd;border-radius:6px;font-size:0.875rem;"
              />
              <%= for {msg, _opts} <- @form[:chat_id].errors do %>
                <p style="color:#dc2626;font-size:0.8rem;margin-top:4px;"><%= msg %></p>
              <% end %>
            </div>
            <button type="submit" style="padding:8px 20px;background:#4f46e5;color:#fff;border:none;border-radius:6px;font-size:0.875rem;cursor:pointer;">
              Lier mon Telegram
            </button>
          </.form>
        <% end %>
      <% end %>
    </div>
    """
  end
end
