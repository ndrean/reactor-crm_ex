defmodule CrmReactor.Emails.MagicLinkEmail do
  @moduledoc "Builds the magic link login email."
  import Swoosh.Email

  def build(to_email, magic_link_url) do
    {from_name, from_email} =
      Application.get_env(:crm_reactor, :mailer_from, {"CRM Reactor", "noreply@crm-reactor.app"})

    new()
    |> to(to_email)
    |> from({from_name, from_email})
    |> subject("Votre lien de connexion CRM Reactor")
    |> text_body("""
    Bonjour,

    Cliquez sur le lien ci-dessous pour vous connecter à CRM Reactor :

    #{magic_link_url}

    Ce lien est valable 15 minutes et ne peut être utilisé qu'une seule fois.

    Si vous n'avez pas demandé ce lien, vous pouvez ignorer cet email.

    Cordialement,
    CRM Reactor
    """)
  end
end
