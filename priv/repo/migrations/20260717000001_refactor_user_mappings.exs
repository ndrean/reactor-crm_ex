defmodule CrmReactor.Repo.Migrations.RefactorUserMappings do
  use Ecto.Migration

  def up do
    # Add new columns
    alter table(:user_mappings, prefix: "global_registry") do
      add :email, :string
      add :telegram_id, :string
    end

    flush()

    # Populate: '@' → email; digits-only → telegram_id
    execute """
    UPDATE global_registry.user_mappings
    SET email = user_identifier
    WHERE user_identifier LIKE '%@%'
    """

    execute """
    UPDATE global_registry.user_mappings
    SET telegram_id = user_identifier,
        email = COALESCE(user_email, 'unknown_' || id || '@placeholder.local')
    WHERE user_identifier ~ '^[0-9]+$' AND email IS NULL
    """

    # Merge: telegram row + email row for same tenant → combine into email row
    execute """
    UPDATE global_registry.user_mappings m_email
    SET telegram_id = m_tg.telegram_id
    FROM global_registry.user_mappings m_tg
    WHERE m_tg.tenant_id = m_email.tenant_id
      AND m_tg.telegram_id IS NOT NULL
      AND m_email.email IS NOT NULL
      AND m_email.telegram_id IS NULL
      AND m_tg.email LIKE '%@placeholder.local'
      AND m_email.email NOT LIKE '%@placeholder.local'
    """

    # Delete merged telegram-only placeholder rows
    execute """
    DELETE FROM global_registry.user_mappings
    WHERE email LIKE '%@placeholder.local'
      AND telegram_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM global_registry.user_mappings m2
        WHERE m2.tenant_id = global_registry.user_mappings.tenant_id
          AND m2.telegram_id = global_registry.user_mappings.telegram_id
          AND m2.id != global_registry.user_mappings.id
      )
    """

    # Drop old columns, enforce NOT NULL
    drop_if_exists index(:user_mappings, [:user_identifier], prefix: "global_registry")

    alter table(:user_mappings, prefix: "global_registry") do
      remove :user_identifier
      remove :user_email
      modify :email, :string, null: false
    end

    create unique_index(:user_mappings, [:email], prefix: "global_registry")

    create unique_index(:user_mappings, [:telegram_id],
             prefix: "global_registry",
             where: "telegram_id IS NOT NULL"
           )
  end

  def down do
    drop_if_exists index(:user_mappings, [:email], prefix: "global_registry")
    drop_if_exists index(:user_mappings, [:telegram_id], prefix: "global_registry")

    alter table(:user_mappings, prefix: "global_registry") do
      add :user_identifier, :string
      add :user_email, :string
    end

    flush()

    # Restore: email → user_identifier
    execute """
    UPDATE global_registry.user_mappings
    SET user_identifier = email, user_email = email
    """

    alter table(:user_mappings, prefix: "global_registry") do
      remove :email
      remove :telegram_id
      modify :user_identifier, :string, null: false
    end

    create unique_index(:user_mappings, [:user_identifier], prefix: "global_registry")
  end
end
