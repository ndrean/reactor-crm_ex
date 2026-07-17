defmodule CrmReactor.Repo.Migrations.CreateGdprAuditLog do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE TABLE global_registry.gdpr_audit_log (
        id            BIGSERIAL PRIMARY KEY,
        action        TEXT      NOT NULL,
        subject_id    TEXT      NOT NULL,
        performed_by  TEXT      NOT NULL,
        details       JSONB,
        performed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      "DROP TABLE global_registry.gdpr_audit_log"
    )

    execute(
      "CREATE INDEX idx_gdpr_audit_log_subject ON global_registry.gdpr_audit_log (subject_id)",
      "DROP INDEX global_registry.idx_gdpr_audit_log_subject"
    )

    execute(
      "CREATE INDEX idx_gdpr_audit_log_performed_at ON global_registry.gdpr_audit_log (performed_at)",
      "DROP INDEX global_registry.idx_gdpr_audit_log_performed_at"
    )
  end
end
