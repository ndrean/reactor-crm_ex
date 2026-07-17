defmodule CrmReactor.Repo.Migrations.NormalizeCreatedByToEmail do
  use Ecto.Migration

  @moduledoc """
  Updates created_by/triggered_by fields in tenant schemas from telegram_id
  to canonical email, using the user_mappings table as the lookup source.
  """

  def up do
    # Get all tenant schemas
    tenants =
      repo().query!(
        "SELECT schema_name FROM global_registry.tenants WHERE schema_name IS NOT NULL",
        []
      )

    # Get telegram_id → email mappings
    mappings =
      repo().query!(
        "SELECT telegram_id, email FROM global_registry.user_mappings WHERE telegram_id IS NOT NULL",
        []
      )

    for [telegram_id, email] <- mappings.rows, [schema] <- tenants.rows do
      # Update execution_logs.triggered_by
      repo().query!(
        "UPDATE #{schema}.execution_logs SET triggered_by = $1 WHERE triggered_by = $2",
        [email, telegram_id]
      )

      # Update todos.created_by
      repo().query!(
        "UPDATE #{schema}.todos SET created_by = $1 WHERE created_by = $2",
        [email, telegram_id]
      )

      # Update expenses.created_by (if table exists)
      repo().query(
        "UPDATE #{schema}.expenses SET created_by = $1 WHERE created_by = $2",
        [email, telegram_id]
      )
    end
  end

  def down do
    # Not reversible — telegram_id data is lost after normalization
    :ok
  end
end
