defmodule CrmReactor.Emails.GdprExportEmail do
  @moduledoc "Builds the GDPR data portability email (Art. 20) with personal data as a JSON attachment."
  import Swoosh.Email

  def build(to_email, data) do
    {from_name, from_email} =
      Application.get_env(:crm_reactor, :mailer_from, {"CRM Reactor", "noreply@crm-reactor.app"})

    json_data = Jason.encode!(data, pretty: true)

    attachment =
      Swoosh.Attachment.new(
        {:data, json_data},
        filename: "donnees_personnelles_#{Date.utc_today()}.json",
        content_type: "application/json"
      )

    Swoosh.Email.new()
    |> to(to_email)
    |> from({from_name, from_email})
    |> subject("Vos données personnelles CRM – #{data.tenant.company_name}")
    |> text_body(
      "Bonjour,\n\nSuite à votre demande, veuillez trouver en pièce jointe l'ensemble des données personnelles que nous détenons vous concernant (Art. 20 RGPD).\n\nCordialement,\nCRM Reactor"
    )
    |> attachment(attachment)
  end
end
