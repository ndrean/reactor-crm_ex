defmodule CrmReactor.Reactors.Modules.DataExport do
  @moduledoc "30-day usage and token cost report — sent by email if admin_email is configured."

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Emails.DataExportEmail
  alias CrmReactor.Mailer
  alias CrmReactor.Repo
  alias CrmReactor.Workers.PendingTimeoutWorker

  @pending_timeout_seconds 15 * 60

  # No admin_email on record: enter the 2-step pending loop to collect one.
  def execute(%{action: "dump", tenant_schema: schema, admin_email: nil, log_id: log_id}) do
    log =
      Repo.get!(ExecutionLog, log_id, prefix: schema)
      |> ExecutionLog.pending_changeset(%{
        action: "dump",
        module: "data",
        proposed_params: %{"type" => "export_email"}
      })
      |> Repo.update!(prefix: schema)

    %{"pending_id" => log.pending_id, "schema_name" => schema}
    |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
    |> Oban.insert()

    {:ok,
     %{
       action: "pending",
       pending_type: "export_email",
       pending_id: log.pending_id,
       output:
         "Pour recevoir votre export par email, quelle est votre adresse email administrateur ?"
     }}
  end

  # admin_email is set: fetch data and send it.
  def execute(%{
        action: "dump",
        tenant_schema: schema,
        admin_email: admin_email,
        company_name: company_name
      }) do
    data_text = fetch_data(schema)

    case DataExportEmail.build(admin_email, company_name, format_output(data_text))
         |> Mailer.deliver() do
      {:ok, _} ->
        {:ok,
         %{
           output: "Vos données ont été envoyées par email à #{admin_email}.",
           action: "dump"
         }}

      {:error, reason} ->
        {:error, {:email_delivery_failed, reason}}
    end
  end

  def execute(%{action: action}) do
    {:ok, %{output: "Action data non supportée : #{action}", action: action}}
  end

  defp fetch_data(schema) do
    result =
      Repo.query!(
        """
        SELECT
          DATE(logged_at) AS date,
          COUNT(*) AS interactions,
          COALESCE(SUM(prompt_tokens), 0) AS prompt_tokens,
          COALESCE(SUM(completion_tokens), 0) AS completion_tokens,
          COALESCE(SUM(total_tokens), 0) AS total_tokens
        FROM #{schema}.execution_logs
        WHERE logged_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(logged_at)
        ORDER BY date DESC
        """,
        []
      )

    Enum.map(result.rows, fn [date, count, pt, ct, tt] ->
      "#{date}: #{count} requêtes, #{tt} tokens (#{pt} prompt + #{ct} completion)"
    end)
  end

  defp format_output([]), do: "Aucune donnée sur les 30 derniers jours."
  defp format_output(rows), do: "Utilisation (30j) :\n" <> Enum.join(rows, "\n")
end
