defmodule CrmReactor.Repo.Migrations.AddWebhookToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants, prefix: "global_registry") do
      add :webhook_url, :text
      add :webhook_secret, :text
    end
  end
end
