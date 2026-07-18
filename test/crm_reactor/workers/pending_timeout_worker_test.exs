defmodule CrmReactor.Workers.PendingTimeoutWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.TestFixtures
  alias CrmReactor.Workers.PendingTimeoutWorker

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    Map.put(fixture, :tenant_map, TestFixtures.tenant_map(fixture))
  end

  test "perform/1 auto-rejects a pending mutation", %{
    user_id: user_id,
    tenant: tenant,
    tenant_map: tenant_map
  } do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "supprime Marie Dupont",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil,
        tenant: tenant_map
      })

    assert result.action == "pending"
    pending_id = result.pending_id

    assert :ok =
             perform_job(PendingTimeoutWorker, %{
               "pending_id" => pending_id,
               "schema_name" => tenant.schema_name
             })
  end

  test "perform/1 returns :ok for non-existent pending_id", %{tenant: tenant} do
    assert :ok =
             perform_job(PendingTimeoutWorker, %{
               "pending_id" => Ecto.UUID.generate(),
               "schema_name" => tenant.schema_name
             })
  end

  test "perform/1 is idempotent - double rejection returns :ok", %{
    user_id: user_id,
    tenant: tenant,
    tenant_map: tenant_map
  } do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "supprime Marie Dupont",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil,
        tenant: tenant_map
      })

    pending_id = result.pending_id

    assert :ok =
             perform_job(PendingTimeoutWorker, %{
               "pending_id" => pending_id,
               "schema_name" => tenant.schema_name
             })

    assert :ok =
             perform_job(PendingTimeoutWorker, %{
               "pending_id" => pending_id,
               "schema_name" => tenant.schema_name
             })
  end

  test "perform/1 with schema_name key auto-rejects", %{
    user_id: user_id,
    tenant: tenant,
    tenant_map: tenant_map
  } do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "supprime Marie Dupont",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil,
        tenant: tenant_map
      })

    assert result.action == "pending"

    assert :ok =
             perform_job(PendingTimeoutWorker, %{
               "pending_id" => result.pending_id,
               "schema_name" => tenant.schema_name
             })
  end

  test "perform/1 with schema_name returns :ok for non-existent pending_id", %{tenant: tenant} do
    assert :ok =
             perform_job(PendingTimeoutWorker, %{
               "pending_id" => Ecto.UUID.generate(),
               "schema_name" => tenant.schema_name
             })
  end
end
