defmodule CrmReactor.Repo.Migrations.AddSuspendedAtToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts, prefix: "global_registry") do
      add :suspended_at, :utc_datetime
    end
  end
end
