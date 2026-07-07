defmodule CrmReactorWeb.ChatLive do
  use CrmReactorWeb, :live_view

  alias CrmReactor.Reactors.MasterIngest
  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.{Storage, Tenants}

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:user_id, "")
     |> assign(:chat_started, false)
     |> assign(:input, "")
     |> assign(:pending, nil)
     |> assign(:email_input, "")
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> stream(:messages, [])
     |> allow_upload(:attachment,
       accept: ~w(.jpg .jpeg .png .gif .csv .txt .vcf),
       max_entries: 1,
       max_file_size: Storage.max_size_bytes()
     )}
  end

  @impl true
  def handle_event("start", %{"user_id" => uid}, socket) when uid != "" do
    {:noreply, assign(socket, chat_started: true, user_id: uid, error: nil)}
  end

  def handle_event("start", _params, socket) do
    {:noreply, assign(socket, error: "Veuillez entrer un identifiant.")}
  end

  @impl true
  def handle_event("validate", %{"input" => input}, socket) do
    {:noreply, assign(socket, input: input)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachment, ref)}
  end

  @impl true
  def handle_event("send", %{"input" => text}, socket) when text != "" do
    attachment = consume_attachment(socket)
    user_msg = %{id: Ecto.UUID.generate(), role: :user, content: text}

    socket =
      socket
      |> stream_insert(:messages, user_msg)
      |> assign(:input, "")
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:pending, nil)

    send(self(), {:run_reactor, text, attachment})
    {:noreply, socket}
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("confirm", _params, socket) do
    %{id: pending_id} = socket.assigns.pending

    case Mutations.confirm(pending_id, "confirm", socket.assigns.user_id) do
      {:ok, result} ->
        msg = %{id: Ecto.UUID.generate(), role: :assistant, content: result.output}
        {:noreply, socket |> stream_insert(:messages, msg) |> assign(:pending, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Erreur : #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reject", _params, socket) do
    %{id: pending_id} = socket.assigns.pending

    case Mutations.confirm(pending_id, "reject", socket.assigns.user_id) do
      {:ok, result} ->
        msg = %{id: Ecto.UUID.generate(), role: :assistant, content: result.output}
        {:noreply, socket |> stream_insert(:messages, msg) |> assign(:pending, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Erreur : #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("provide_email", %{"email" => email}, socket) when email != "" do
    %{id: pending_id} = socket.assigns.pending

    case Mutations.confirm(pending_id, email, socket.assigns.user_id) do
      {:ok, result} ->
        msg = %{id: Ecto.UUID.generate(), role: :assistant, content: result.output}

        {:noreply,
         socket
         |> stream_insert(:messages, msg)
         |> assign(:pending, nil)
         |> assign(:email_input, "")}

      {:error, :invalid_email} ->
        {:noreply, assign(socket, error: "Adresse email invalide.")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Erreur : #{inspect(reason)}")}
    end
  end

  def handle_event("provide_email", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:run_reactor, text, attachment}, socket) do
    job_id = "web-#{Ecto.UUID.generate()}"

    result =
      Reactor.run(MasterIngest, %{
        user_id: socket.assigns.user_id,
        raw_input: text,
        is_audio: false,
        channel: :http,
        job_id: job_id,
        attachment: attachment
      })

    case result do
      {:ok, res} ->
        msg = %{id: Ecto.UUID.generate(), role: :assistant, content: res.output}

        pending =
          if res.action == "pending" do
            %{id: res.pending_id, type: res[:pending_type]}
          end

        {:noreply,
         socket
         |> stream_insert(:messages, msg)
         |> assign(:loading, false)
         |> assign(:pending, pending)}

      {:error, %{errors: [%{error: :unknown_user} | _]}} ->
        {:noreply,
         assign(socket,
           loading: false,
           error: "Identifiant inconnu. Vérifiez votre identifiant et réessayez."
         )}

      {:error, reason} ->
        Logger.error("Reactor failed: #{inspect(reason)}")

        {:noreply,
         assign(socket, loading: false, error: "Une erreur est survenue. Veuillez réessayer.")}
    end
  end

  defp consume_attachment(socket) do
    with {[_ | _], []} <- uploaded_entries(socket, :attachment),
         {:ok, schema} <- Tenants.schema_for_user(socket.assigns.user_id) do
      [result] =
        consume_uploaded_entries(socket, :attachment, fn %{path: path}, entry ->
          content = File.read!(path)
          store_attachment(schema, entry, content)
        end)

      result
    else
      _ -> nil
    end
  end

  defp store_attachment(schema, entry, content) do
    case Storage.put(schema, entry.client_name, content) do
      {:ok, key} ->
        {:ok,
         %{
           storage_key: key,
           filename: entry.client_name,
           content_type: entry.client_type,
           size_bytes: byte_size(content)
         }}

      {:error, _} ->
        {:ok, nil}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-wrap">
      <h1 style="font-size: 1.4rem; font-weight: 700; margin-bottom: 24px; color: #2563eb;">
        CRM Assistant
      </h1>

      <%= if not @chat_started do %>
        <div style="background: #fff; border-radius: 12px; padding: 32px; box-shadow: 0 1px 4px rgba(0,0,0,0.1);">
          <p style="margin-bottom: 16px; color: #555;">
            Entrez votre identifiant pour commencer (ex&nbsp;: votre numéro de téléphone).
          </p>
          <form phx-submit="start" style="display: flex; gap: 8px;">
            <input
              type="text"
              name="user_id"
              value={@user_id}
              placeholder="1234567890"
              autofocus
              style="flex: 1; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
            />
            <button
              type="submit"
              style="padding: 10px 20px; background: #2563eb; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer;"
            >
              Démarrer
            </button>
          </form>
          <%= if @error do %>
            <p style="color: #dc2626; margin-top: 10px; font-size: 0.9rem;"><%= @error %></p>
          <% end %>
        </div>
      <% else %>
        <div style="background: #fff; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); display: flex; flex-direction: column; height: calc(100vh - 120px);">
          <%!-- Message list using LiveView streams --%>
          <div
            id="messages"
            phx-update="stream"
            style="flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 12px;"
          >
            <div
              :for={{dom_id, msg} <- @streams.messages}
              id={dom_id}
              style={
                if msg.role == :user,
                  do:
                    "align-self: flex-end; background: #2563eb; color: #fff; padding: 10px 14px; border-radius: 12px 12px 2px 12px; max-width: 75%; white-space: pre-wrap;",
                  else:
                    "align-self: flex-start; background: #f3f4f6; color: #1a1a1a; padding: 10px 14px; border-radius: 12px 12px 12px 2px; max-width: 75%; white-space: pre-wrap;"
              }
            >
              <%= msg.content %>
            </div>
          </div>

          <%= if @loading do %>
            <div style="padding: 0 20px 8px; color: #9ca3af; font-style: italic; font-size: 0.9rem;">
              En cours…
            </div>
          <% end %>

          <%!-- Error banner --%>
          <%= if @error do %>
            <div style="margin: 0 16px 8px; padding: 10px 14px; background: #fee2e2; color: #dc2626; border-radius: 8px; font-size: 0.9rem;">
              <%= @error %>
            </div>
          <% end %>

          <%!-- Pending actions or message input --%>
          <div style="padding: 16px; border-top: 1px solid #e5e7eb;">
            <%= if @pending do %>
              <%= if @pending.type == "export_email" do %>
                <form phx-submit="provide_email" style="display: flex; gap: 8px;">
                  <input
                    type="email"
                    name="email"
                    value={@email_input}
                    placeholder="admin@exemple.fr"
                    autofocus
                    style="flex: 1; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
                  />
                  <button
                    type="submit"
                    style="padding: 10px 20px; background: #2563eb; color: #fff; border: none; border-radius: 8px; cursor: pointer;"
                  >
                    Envoyer
                  </button>
                </form>
              <% else %>
                <div style="display: flex; gap: 8px;">
                  <button
                    phx-click="confirm"
                    style="flex: 1; padding: 10px; background: #16a34a; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer;"
                  >
                    Confirmer
                  </button>
                  <button
                    phx-click="reject"
                    style="flex: 1; padding: 10px; background: #6b7280; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer;"
                  >
                    Annuler
                  </button>
                </div>
              <% end %>
            <% else %>
              <form id="chat-input-form" phx-submit="send" phx-change="validate" style="display: flex; flex-direction: column; gap: 8px;">
                <%!-- Selected file indicator --%>
                <%= for entry <- @uploads.attachment.entries do %>
                  <div style="display: flex; align-items: center; gap: 6px; font-size: 0.85rem; color: #374151; background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 6px; padding: 4px 10px;">
                    <span>📎 <%= entry.client_name %></span>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      style="margin-left: auto; background: none; border: none; color: #6b7280; cursor: pointer; font-size: 1rem; line-height: 1;"
                    >
                      ×
                    </button>
                  </div>
                <% end %>
                <div style="display: flex; gap: 8px;">
                  <label style="display: flex; align-items: center; justify-content: center; padding: 10px 12px; background: #f3f4f6; border: 1px solid #d1d5db; border-radius: 8px; cursor: pointer;" title="Joindre un fichier">
                    📎
                    <.live_file_input upload={@uploads.attachment} style="display: none;" />
                  </label>
                  <input
                    type="text"
                    name="input"
                    value={@input}
                    placeholder="Tapez votre message…"
                    autofocus={not @loading}
                    disabled={@loading}
                    style="flex: 1; padding: 10px 14px; border: 1px solid #d1d5db; border-radius: 8px; font-size: 1rem;"
                  />
                  <button
                    type="submit"
                    disabled={@loading}
                    style="padding: 10px 20px; background: #2563eb; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer;"
                  >
                    Envoyer
                  </button>
                </div>
              </form>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
