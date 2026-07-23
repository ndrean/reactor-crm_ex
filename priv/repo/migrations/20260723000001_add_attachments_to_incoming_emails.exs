defmodule CrmReactor.Repo.Migrations.AddAttachmentsToIncomingEmails do
  use Ecto.Migration

  def change do
    alter table(:incoming_emails, prefix: "global_registry") do
      add :attachments, {:array, :map}, default: []
    end
  end
end
