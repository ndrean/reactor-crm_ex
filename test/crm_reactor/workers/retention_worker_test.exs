defmodule CrmReactor.Workers.RetentionWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.TestFixtures
  alias CrmReactor.Workers.RetentionWorker

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  defp create_log(user_id) do
    Reactor.run(CrmReactor.Reactors.MasterIngest, %{
      user_id: user_id,
      raw_input: "cherche Marie",
      is_audio: false,
      channel: :http,
      job_id: nil,
      attachment: nil
    })
  end

  defp backdate_logs(schema) do
    Repo.query!("UPDATE #{schema}.execution_logs SET logged_at = NOW() - INTERVAL '181 days'")
  end

  test "anonymizes execution logs older than 180 days", %{user_id: user_id, tenant: tenant} do
    create_log(user_id)
    backdate_logs(tenant.schema_name)

    assert :ok = perform_job(RetentionWorker, %{})

    logs = Repo.all(ExecutionLog, prefix: tenant.schema_name)
    assert length(logs) == 1
    assert Enum.all?(logs, &(&1.raw_input == "[RETAINED]"))
    assert Enum.all?(logs, &(&1.output == "[RETAINED]"))
  end

  test "leaves recent logs untouched", %{user_id: user_id, tenant: tenant} do
    create_log(user_id)

    assert :ok = perform_job(RetentionWorker, %{})

    [log] = Repo.all(ExecutionLog, prefix: tenant.schema_name)
    assert log.raw_input == "cherche Marie"
  end

  test "does not re-anonymize already retained logs", %{user_id: user_id, tenant: tenant} do
    create_log(user_id)
    backdate_logs(tenant.schema_name)

    Repo.query!(
      "UPDATE #{tenant.schema_name}.execution_logs SET raw_input = '[RETAINED]', output = '[RETAINED]'"
    )

    assert :ok = perform_job(RetentionWorker, %{})
    assert :ok = perform_job(RetentionWorker, %{})

    [log] = Repo.all(ExecutionLog, prefix: tenant.schema_name)
    assert log.raw_input == "[RETAINED]"
  end

  test "skips erased logs", %{user_id: user_id, tenant: tenant} do
    create_log(user_id)
    backdate_logs(tenant.schema_name)

    Repo.query!(
      "UPDATE #{tenant.schema_name}.execution_logs SET status = 'erased', raw_input = '[REDACTED]', output = '[REDACTED]'"
    )

    assert :ok = perform_job(RetentionWorker, %{})

    [log] = Repo.all(ExecutionLog, prefix: tenant.schema_name)
    assert log.raw_input == "[REDACTED]"
    assert log.status == "erased"
  end
end
