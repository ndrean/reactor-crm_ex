defmodule CrmReactor.Emails.DataExportEmail do
  @moduledoc "Builds the data export email with the 30-day usage report as a text attachment."
  import Swoosh.Email

  def build(to_email, company_name, data_text) do
    {from_name, from_email} =
      Application.get_env(:crm_reactor, :mailer_from, {"CRM Reactor", "noreply@crm-reactor.app"})

    attachment =
      Swoosh.Attachment.new(
        {:data, data_text},
        filename: "export_crm_#{Date.utc_today()}.txt",
        content_type: "text/plain"
      )

    new()
    |> to(to_email)
    |> from({from_name, from_email})
    |> subject("Votre export de données CRM – #{company_name}")
    |> text_body(
      "Bonjour,\n\nVeuillez trouver en pièce jointe votre export d'utilisation des 30 derniers jours.\n\nCordialement,\nCRM Reactor"
    )
    |> attachment(attachment)
  end
end
