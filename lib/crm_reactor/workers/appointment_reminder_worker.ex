defmodule CrmReactor.Workers.AppointmentReminderWorker do
  @moduledoc "Oban worker: sends appointment reminders N minutes before starts_at."
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias CrmReactor.CRM.Todo
  alias CrmReactor.Repo

  require Logger

  @impl true
  def perform(%Oban.Job{
        args: %{
          "todo_id" => todo_id,
          "tenant_schema" => schema,
          "channel" => channel,
          "user_id" => user_id,
          "subject" => subject
        }
      }) do
    case Repo.get(Todo, todo_id, prefix: schema) do
      nil ->
        Logger.info("Appointment reminder: todo #{todo_id} not found, skipping")
        :ok

      %{done: true} ->
        Logger.info("Appointment reminder: todo #{todo_id} already done, skipping")
        :ok

      _todo ->
        deliver_reminder(channel, user_id, subject, schema)
    end
  end

  defp deliver_reminder("telegram", user_id, subject, _schema) do
    text = "⏰ Rappel : #{subject}"

    case Application.get_env(:crm_reactor, :telegram_bot) do
      nil ->
        Logger.warning("Telegram bot not configured, reminder not sent: #{text}")
        :ok

      bot_module ->
        bot_module.send_message(user_id, text)
        :ok
    end
  end

  defp deliver_reminder(_channel, _user_id, subject, schema) do
    # For HTTP channel, enqueue a webhook delivery if tenant has webhook_url
    case Repo.query(
           "SELECT webhook_url FROM global_registry.tenants WHERE schema_name = $1",
           [schema]
         ) do
      {:ok, %{rows: [[url]]}} when is_binary(url) ->
        %{
          "tenant_schema" => schema,
          "payload" => %{"type" => "reminder", "subject" => subject}
        }
        |> CrmReactor.Workers.WebhookWorker.new()
        |> Oban.insert()

        :ok

      _ ->
        Logger.info("No webhook configured for #{schema}, reminder logged: #{subject}")
        :ok
    end
  end
end
