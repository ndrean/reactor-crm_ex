defmodule CrmReactor.Repo.Migrations.AddHintEmbeddingToModuleRegistry do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE global_registry.module_registry ADD COLUMN hint_embedding float8[]"
  end

  def down do
    execute "ALTER TABLE global_registry.module_registry DROP COLUMN IF EXISTS hint_embedding"
  end
end
