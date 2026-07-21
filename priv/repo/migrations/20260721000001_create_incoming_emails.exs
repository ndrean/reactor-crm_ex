defmodule CrmReactor.Repo.Migrations.CreateIncomingEmails do
  use Ecto.Migration

  def change do
    create table(:incoming_emails, prefix: "global_registry") do
      add :from_address, :string, null: false
      add :subject, :string
      add :body_text, :text
      add :status, :string, null: false, default: "pending"
      add :received_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:incoming_emails, [:status], prefix: "global_registry")
    create index(:incoming_emails, [:received_at], prefix: "global_registry")
  end
end
