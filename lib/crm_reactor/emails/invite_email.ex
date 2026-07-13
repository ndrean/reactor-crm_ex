defmodule CrmReactor.Emails.InviteEmail do
  @moduledoc "Builds the invitation email sent to new user accounts."
  import Swoosh.Email

  def build(to_email, name, invite_url) do
    {from_name, from_email} =
      Application.get_env(:crm_reactor, :mailer_from, {"CRM Reactor", "noreply@crm-reactor.app"})

    greeting = if name, do: "Bonjour #{name},", else: "Bonjour,"

    new()
    |> to(to_email)
    |> from({from_name, from_email})
    |> subject("Votre invitation CRM Reactor")
    |> text_body("""
    #{greeting}

    Un compte a été créé pour vous sur CRM Reactor.

    Cliquez sur le lien ci-dessous pour définir votre mot de passe et activer votre compte :

    #{invite_url}

    Ce lien est valable 24 heures.

    Cordialement,
    CRM Reactor
    """)
  end
end
