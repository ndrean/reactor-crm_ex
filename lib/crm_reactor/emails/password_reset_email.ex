defmodule CrmReactor.Emails.PasswordResetEmail do
  @moduledoc "Builds the password reset email sent to existing user accounts."
  import Swoosh.Email

  def build(to_email, name, reset_url) do
    {from_name, from_email} =
      Application.get_env(:crm_reactor, :mailer_from, {"CRM Reactor", "noreply@crm-reactor.app"})

    greeting = if name, do: "Bonjour #{name},", else: "Bonjour,"

    new()
    |> to(to_email)
    |> from({from_name, from_email})
    |> subject("Réinitialisation de votre mot de passe CRM Reactor")
    |> text_body("""
    #{greeting}

    Une demande de réinitialisation de mot de passe a été effectuée pour votre compte.

    Cliquez sur le lien ci-dessous pour définir un nouveau mot de passe :

    #{reset_url}

    Ce lien est valable 24 heures.

    Si vous n'avez pas demandé cette réinitialisation, vous pouvez ignorer cet e-mail.

    Cordialement,
    CRM Reactor
    """)
  end
end
