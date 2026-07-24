defmodule CrmReactorWeb.Router do
  use CrmReactorWeb, :router

  import Phoenix.LiveDashboard.Router

  import CrmReactorWeb.Plugs.AccountAuth,
    only: [fetch_current_account: 2, redirect_if_authenticated: 2, require_admin: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CrmReactorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CrmReactorWeb.Plugs.CSP
    plug :fetch_current_account
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :rate_limited do
    plug CrmReactorWeb.Plugs.RateLimiter
  end

  pipeline :login_rate_limited do
    plug CrmReactorWeb.Plugs.RateLimiter, max: 5, window_ms: 60_000, prefix: "login"
  end

  pipeline :admin_api_rate_limited do
    plug CrmReactorWeb.Plugs.RateLimiter, max: 60, window_ms: 60_000, prefix: "admin_api"
  end

  pipeline :signed_webhook do
    plug CrmReactorWeb.Plugs.WebhookSignature,
      secret_key: :email_webhook_secret,
      header: "x-webhook-signature"
  end

  # Public: login page (redirects if already logged in)
  scope "/", CrmReactorWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    live_session :redirect_if_authenticated,
      on_mount: [{CrmReactorWeb.AccountAuth, :redirect_if_authenticated}] do
      live "/login", LoginLive, :index
    end
  end

  # Public: session create/delete (POST endpoints for phx-trigger-action)
  scope "/", CrmReactorWeb do
    pipe_through [:browser, :login_rate_limited]

    post "/login", AccountSessionController, :create
  end

  scope "/", CrmReactorWeb do
    pipe_through :browser

    get "/login/magic/:token", AccountSessionController, :magic_link
    delete "/logout", AccountSessionController, :delete
  end

  # Public: invite accept flow
  scope "/", CrmReactorWeb do
    pipe_through :browser

    get "/invite/:token", InviteController, :show
    post "/invite/:token", InviteController, :accept
  end

  # Public: Telegram onboarding (no auth required)
  scope "/", CrmReactorWeb do
    pipe_through :browser

    live_session :onboard do
      live "/onboard/:token", OnboardLive, :index
    end
  end

  # Bootstrap: first-time admin setup (public, rate-limited)
  scope "/", CrmReactorWeb do
    pipe_through [:browser, :login_rate_limited]

    live_session :bootstrap do
      live "/setup", BootstrapLive, :index
    end
  end

  # Root redirect to login
  scope "/", CrmReactorWeb do
    pipe_through :browser

    get "/", AccountSessionController, :root
  end

  # User chat (requires confirmed user account)
  scope "/", CrmReactorWeb do
    pipe_through :browser

    live_session :user,
      on_mount: [{CrmReactorWeb.AccountAuth, :ensure_user}] do
      live "/chat", ChatLive, :index
    end
  end

  # Admin dashboard (requires admin account)
  scope "/admin", CrmReactorWeb do
    pipe_through [:browser, :require_admin]

    live_dashboard "/dashboard",
      ecto_repos: CrmReactor.Repo

    live_session :admin,
      on_mount: [{CrmReactorWeb.AccountAuth, :ensure_admin}],
      root_layout: {CrmReactorWeb.Layouts, :admin_root} do
      live "/", AdminLive.Dashboard, :index
      live "/tenants", AdminLive.Tenants, :index
      live "/users", AdminLive.Users, :index
      live "/subscriptions", AdminLive.Subscriptions, :index
      live "/setup", AdminLive.TelegramSetup, :index
      live "/system", AdminLive.System, :index
      live "/incoming-emails", AdminLive.IncomingEmails, :index
    end
  end

  scope "/cal", CrmReactorWeb do
    pipe_through [:rate_limited]

    get "/:token", CalendarFeedController, :show
  end

  scope "/api", CrmReactorWeb do
    pipe_through :api

    get "/health", HealthController, :check
  end

  scope "/api", CrmReactorWeb do
    pipe_through [:api, :admin_api_rate_limited]

    post "/admin/provision", AdminController, :provision
    post "/admin/toggle", AdminController, :toggle
    put "/admin/subscriptions", AdminController, :set_subscription
    put "/admin/webhook", AdminController, :set_webhook
    get "/admin/webhook_secret", AdminController, :get_webhook_secret
    get "/admin/subjects/:identifier/export", AdminController, :export_subject
    post "/admin/subjects/:identifier/email-export", AdminController, :email_subject
    delete "/admin/subjects/:identifier", AdminController, :erase_subject
    delete "/admin/contacts/:schema/:contact_id", AdminController, :erase_contact
  end

  scope "/api", CrmReactorWeb do
    pipe_through [:api, :rate_limited]

    post "/crm", CrmController, :ingest
    post "/crm/confirm", CrmController, :confirm
  end

  scope "/webhook", CrmReactorWeb do
    pipe_through [:api, :rate_limited]

    post "/telegram", WebhookController, :telegram
  end

  scope "/webhook", CrmReactorWeb do
    pipe_through [:api, :rate_limited, :signed_webhook]

    post "/email", InboundEmailController, :create
  end

  scope "/", CrmReactorWeb do
    pipe_through [:api, :admin_api_rate_limited]

    get "/metrics", MetricsController, :index
  end

  if Application.compile_env(:crm_reactor, :dev_routes, false) do
    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end
end
