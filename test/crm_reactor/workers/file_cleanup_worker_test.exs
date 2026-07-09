defmodule CrmReactor.Workers.FileCleanupWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.CRM.{ExecutionAttachment, ExecutionLog}
  alias CrmReactor.Repo
  alias CrmReactor.TestFixtures
  alias CrmReactor.Workers.FileCleanupWorker

  import Ecto.Query

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    schema = fixture.tenant.schema_name

    %{schema: schema, user_id: fixture.user_id}
  end

  defp insert_log_with_attachment(schema, user_id, logged_at) do
    log =
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: user_id,
        channel: "http",
        raw_input: "test upload"
      })
      |> Repo.insert!(prefix: schema)

    # Backdate the log
    from(e in ExecutionLog, where: e.id == ^log.id)
    |> Repo.update_all([set: [logged_at: logged_at]], prefix: schema)

    # Write a test file
    storage_path = Application.get_env(:crm_reactor, :storage_path, "priv/uploads")
    key = "#{schema}/test-#{log.id}-file.txt"
    path = Path.join(storage_path, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "test content")

    attachment =
      %ExecutionAttachment{}
      |> ExecutionAttachment.changeset(%{
        execution_log_id: log.id,
        filename: "file.txt",
        content_type: "text/plain",
        size_bytes: 12,
        storage_key: key
      })
      |> Repo.insert!(prefix: schema)

    {log, attachment, path}
  end

  test "deletes files and attachment records older than retention period", %{
    schema: schema,
    user_id: user_id
  } do
    old_date = DateTime.utc_now() |> DateTime.add(-200 * 86_400) |> DateTime.truncate(:second)
    {_log, attachment, path} = insert_log_with_attachment(schema, user_id, old_date)

    assert File.exists?(path)

    assert :ok = perform_job(FileCleanupWorker, %{})

    refute File.exists?(path)

    refute Repo.one(
             from(a in ExecutionAttachment, where: a.id == ^attachment.id),
             prefix: schema
           )
  end

  test "does not delete files within retention period", %{schema: schema, user_id: user_id} do
    recent_date = DateTime.utc_now() |> DateTime.add(-10 * 86_400) |> DateTime.truncate(:second)
    {_log, attachment, path} = insert_log_with_attachment(schema, user_id, recent_date)

    assert File.exists?(path)

    assert :ok = perform_job(FileCleanupWorker, %{})

    assert File.exists?(path)

    assert Repo.one(
             from(a in ExecutionAttachment, where: a.id == ^attachment.id),
             prefix: schema
           )

    # Cleanup
    File.rm(path)
  end

  test "no-ops when no attachments exist", %{} do
    assert :ok = perform_job(FileCleanupWorker, %{})
  end
end
