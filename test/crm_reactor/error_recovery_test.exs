defmodule CrmReactor.ErrorRecoveryTest do
  @moduledoc """
  Tests that verify error recovery when the pipeline fails after
  LogExecution has already inserted a record. Ensures no stuck
  "processing" logs and no duplicates on retry.
  """
  use CrmReactor.DataCase

  alias CrmReactor.CRM.ExecutionLog
  alias CrmReactor.TestFixtures

  import Ecto.Query

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    Map.put(fixture, :tenant_map, TestFixtures.tenant_map(fixture))
  end

  describe "classifier crash after log creation" do
    setup do
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.CrashingClassifier)

      on_exit(fn ->
        Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.MockClassifier)
      end)
    end

    test "reactor returns error", %{user_id: user_id, tenant_map: tenant_map} do
      assert {:error, _} =
               Reactor.run(CrmReactor.Reactors.MasterIngest, %{
                 user_id: user_id,
                 raw_input: "cherche Marie",
                 is_audio: false,
                 channel: :http,
                 job_id: nil,
                 attachment: nil,
                 tenant: tenant_map
               })
    end

    test "log is left as processing without job_id (no worker recovery)", %{
      user_id: user_id,
      tenant: tenant,
      tenant_map: tenant_map
    } do
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil,
        tenant: tenant_map
      })

      logs = Repo.all(ExecutionLog, prefix: tenant.schema_name)
      assert [%{status: "processing"}] = logs
    end

    test "log is marked as error with job_id (worker recovery)", %{
      user_id: user_id,
      tenant: tenant,
      tenant_map: tenant_map
    } do
      job_id = "test-#{System.unique_integer([:positive])}"

      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: job_id,
        attachment: nil,
        tenant: tenant_map
      })

      # Simulate what IngestWorker.mark_log_failed does
      log =
        Repo.one!(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: tenant.schema_name)

      assert log.status == "processing"

      log
      |> ExecutionLog.error_changeset(%{error_message: "LLM unavailable (test crash)"})
      |> Repo.update!(prefix: tenant.schema_name)

      updated =
        Repo.one!(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: tenant.schema_name)

      assert updated.status == "error"
      assert updated.error_message =~ "LLM unavailable"
      assert updated.completed_at != nil
    end

    test "retry reuses same log row via job_id (no duplicates)", %{
      user_id: user_id,
      tenant: tenant,
      tenant_map: tenant_map
    } do
      job_id = "retry-test-#{System.unique_integer([:positive])}"

      input = %{
        user_id: user_id,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: job_id,
        attachment: nil,
        tenant: tenant_map
      }

      # First attempt: creates log, classifier crashes
      Reactor.run(CrmReactor.Reactors.MasterIngest, input)

      assert Repo.aggregate(from(l in ExecutionLog, where: l.job_id == ^job_id), :count,
               prefix: tenant.schema_name
             ) == 1

      # Mark as error (simulating worker)
      log =
        Repo.one!(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: tenant.schema_name)

      log
      |> ExecutionLog.error_changeset(%{error_message: "attempt 1"})
      |> Repo.update!(prefix: tenant.schema_name)

      # Second attempt (retry): should reuse same row, reset to processing
      Reactor.run(CrmReactor.Reactors.MasterIngest, input)

      assert Repo.aggregate(from(l in ExecutionLog, where: l.job_id == ^job_id), :count,
               prefix: tenant.schema_name
             ) == 1

      retried =
        Repo.one!(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: tenant.schema_name)

      assert retried.status == "processing"
      assert retried.error_message == nil
    end
  end

  describe "successful pipeline after retry" do
    test "log transitions from error to completed on successful retry", %{
      user_id: user_id,
      tenant: tenant,
      tenant_map: tenant_map
    } do
      job_id = "recovery-#{System.unique_integer([:positive])}"

      input = %{
        user_id: user_id,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: job_id,
        attachment: nil,
        tenant: tenant_map
      }

      # First attempt: crash
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.CrashingClassifier)
      Reactor.run(CrmReactor.Reactors.MasterIngest, input)

      log =
        Repo.one!(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: tenant.schema_name)

      log
      |> ExecutionLog.error_changeset(%{error_message: "crash"})
      |> Repo.update!(prefix: tenant.schema_name)

      # Second attempt: classifier is back
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.MockClassifier)
      {:ok, _result} = Reactor.run(CrmReactor.Reactors.MasterIngest, input)

      # Only one log, now completed
      assert Repo.aggregate(from(l in ExecutionLog, where: l.job_id == ^job_id), :count,
               prefix: tenant.schema_name
             ) == 1

      recovered =
        Repo.one!(from(l in ExecutionLog, where: l.job_id == ^job_id), prefix: tenant.schema_name)

      assert recovered.status == "completed"
      assert recovered.error_message == nil
      assert recovered.completed_at != nil
    end
  end
end
