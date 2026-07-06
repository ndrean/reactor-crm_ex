defmodule CrmReactor.Workers.IngestWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.TestFixtures
  alias CrmReactor.Workers.IngestWorker

  import Ecto.Query

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  test "perform/1 returns :ok on success", %{user_id: user_id} do
    assert :ok =
             perform_job(IngestWorker, %{
               "user_id" => user_id,
               "text" => "cherche Marie",
               "channel" => "http",
               "is_audio" => false
             })
  end

  test "perform/1 returns error for unknown user" do
    assert {:error, _} =
             perform_job(IngestWorker, %{
               "user_id" => "0000000000",
               "text" => "hello",
               "channel" => "http",
               "is_audio" => false
             })
  end

  test "perform/1 marks execution log as error when reactor crashes", %{
    user_id: user_id,
    tenant: tenant
  } do
    Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.CrashingClassifier)

    on_exit(fn ->
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.MockClassifier)
    end)

    assert {:error, _} =
             perform_job(IngestWorker, %{
               "user_id" => user_id,
               "text" => "cherche Marie",
               "channel" => "http",
               "is_audio" => false
             })

    error_logs =
      Repo.all(from(l in ExecutionLog, where: l.status == "error"), prefix: tenant.schema_name)

    assert [%{error_message: msg}] = error_logs
    assert msg =~ "LLM unavailable"
  end

  test "perform/1 returns error when Telegram send fails (triggers Oban retry)", %{
    user_id: user_id
  } do
    Application.put_env(:crm_reactor, :telegram_client, CrmReactor.Telegram.MockSender)
    on_exit(fn -> Application.delete_env(:crm_reactor, :telegram_client) end)

    assert {:error, {:send_failed, :timeout}} =
             perform_job(IngestWorker, %{
               "user_id" => user_id,
               "text" => "cherche Marie",
               "channel" => "telegram",
               "chat_id" => "5555555555",
               "is_audio" => false
             })
  end

  test "perform/1 creates log with job_id on success", %{user_id: user_id, tenant: tenant} do
    assert :ok =
             perform_job(IngestWorker, %{
               "user_id" => user_id,
               "text" => "cherche Marie",
               "channel" => "http",
               "is_audio" => false
             })

    logs = Repo.all(ExecutionLog, prefix: tenant.schema_name)
    assert [%{status: "completed", job_id: "oban-" <> _}] = logs
  end
end
