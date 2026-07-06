defmodule CrmReactorWeb.Router do
  use CrmReactorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CrmReactorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :rate_limited do
    plug CrmReactorWeb.Plugs.RateLimiter
  end

  scope "/", CrmReactorWeb do
    pipe_through :browser

    live "/chat", ChatLive, :index
  end

  scope "/api", CrmReactorWeb do
    pipe_through :api

    get "/health", HealthController, :check
    post "/admin/provision", AdminController, :provision
    post "/admin/toggle", AdminController, :toggle
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

  get "/metrics", CrmReactorWeb.MetricsController, :index
end
