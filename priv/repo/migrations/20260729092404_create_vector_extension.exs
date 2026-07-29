defmodule CrmReactor.Repo.Migrations.CreateVectorExtension do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"
  end
end
