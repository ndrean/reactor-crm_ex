defmodule CrmReactor.Repo.Migrations.AllowNullHashedPassword do
  use Ecto.Migration

  def change do
    alter table(:accounts, prefix: "global_registry") do
      modify :hashed_password, :string, null: true, from: {:string, null: false}
    end
  end
end
