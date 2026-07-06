defmodule CrmReactor.Repo do
  use Ecto.Repo,
    otp_app: :crm_reactor,
    adapter: Ecto.Adapters.Postgres
end
