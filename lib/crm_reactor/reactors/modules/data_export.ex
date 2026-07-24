defmodule CrmReactor.Reactors.Modules.DataExport do
  @moduledoc "30-day usage and token cost report — sent by email if admin_email is configured."

  import Ecto.Query

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.Emails.DataExportEmail
  alias CrmReactor.Mailer
  alias CrmReactor.Reactors.PendingHelper
  alias CrmReactor.Repo

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

    PendingHelper.schedule_pending_timeout(log.pending_id, schema)

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
    query =
      from(e in "execution_logs",
        where: e.logged_at >= ago(30, "day"),
        group_by: fragment("DATE(?)", e.logged_at),
        order_by: [desc: fragment("DATE(?)", e.logged_at)],
        select: %{
          date: fragment("DATE(?)", e.logged_at),
          interactions: count(e.id),
          prompt_tokens: coalesce(sum(e.prompt_tokens), 0),
          completion_tokens: coalesce(sum(e.completion_tokens), 0),
          total_tokens: coalesce(sum(e.total_tokens), 0)
        }
      )

    Repo.all(query, prefix: schema)
    |> Enum.map(fn row ->
      "#{row.date}: #{row.interactions} requêtes, #{row.total_tokens} tokens (#{row.prompt_tokens} prompt + #{row.completion_tokens} completion)"
    end)
  end

  defp format_output([]), do: "Aucune donnée sur les 30 derniers jours."
  defp format_output(rows), do: "Utilisation (30j) :\n" <> Enum.join(rows, "\n")
end
