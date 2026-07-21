defmodule CrmReactor.Emails.InviteEmail do
  @moduledoc "Builds the invitation email sent to new user accounts."
  import Swoosh.Email

  def build(to_email, name, invite_url, calendar_url \\ nil, onboard_url \\ nil) do
    {from_name, from_email} =
      Application.get_env(:crm_reactor, :mailer_from, {"CRM Reactor", "noreply@crm-reactor.app"})

    greeting = if name, do: "Bonjour #{name},", else: "Bonjour,"

    calendar_section =
      if calendar_url do
        """

        ── Calendrier ──
        Ajoutez ce calendrier à votre application (Google Calendar, Apple Calendar, etc.) :
        #{calendar_url}
        """
      else
        ""
      end

    telegram_section =
      if onboard_url do
        """

        ── Notifications Telegram ──
        Pour recevoir vos rappels par Telegram :
        1. Envoyez /start à @GetMyIDBot sur Telegram pour obtenir votre chat ID
        2. Cliquez ici pour lier votre Telegram : #{onboard_url}
        Ce lien est valable 7 jours.
        """
      else
        ""
      end

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
    #{calendar_section}#{telegram_section}
    Cordialement,
    CRM Reactor
    """)
  end
end
