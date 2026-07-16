defmodule CrmReactor.Workers.AppointmentReminderWorkerTest do
  use CrmReactor.DataCase
  use Oban.Testing, repo: CrmReactor.Repo

  alias CrmReactor.CRM.Todo
  alias CrmReactor.{Repo, TestFixtures}
  alias CrmReactor.Workers.AppointmentReminderWorker

  setup do
    fixture = TestFixtures.provision_test_tenant("reminder")
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  test "returns :ok when todo is not found", %{tenant: tenant} do
    assert :ok =
             perform_job(AppointmentReminderWorker, %{
               "todo_id" => 999_999,
               "tenant_schema" => tenant.schema_name,
               "channel" => "http",
               "user_id" => "12345",
               "subject" => "Ghost appointment"
             })
  end

  test "returns :ok when todo is already done", %{tenant: tenant, user_id: user_id} do
    # Find a todo and mark it done
    todo =
      Repo.all(Todo, prefix: tenant.schema_name)
      |> List.first()

    todo
    |> Ecto.Changeset.change(%{done: true})
    |> Repo.update!(prefix: tenant.schema_name)

    assert :ok =
             perform_job(AppointmentReminderWorker, %{
               "todo_id" => todo.id,
               "tenant_schema" => tenant.schema_name,
               "channel" => "http",
               "user_id" => user_id,
               "subject" => todo.subject
             })
  end

  test "returns :ok for http channel with no webhook configured", %{
    tenant: tenant,
    user_id: user_id
  } do
    # The test tenant has no webhook_url set by default
    todo =
      Repo.all(Todo, prefix: tenant.schema_name)
      |> Enum.find(&(&1.starts_at != nil))

    assert todo, "Expected an appointment-type todo in fixtures"

    assert :ok =
             perform_job(AppointmentReminderWorker, %{
               "todo_id" => todo.id,
               "tenant_schema" => tenant.schema_name,
               "channel" => "http",
               "user_id" => user_id,
               "subject" => todo.subject
             })
  end

  test "enqueues WebhookWorker for http channel with webhook configured", %{
    tenant: tenant,
    user_id: user_id
  } do
    # Set up webhook on tenant
    alias CrmReactor.Tenants.Provisioner
    {:ok, _tenant} = Provisioner.set_webhook(tenant.tenant_id, "https://example.com/hook")

    todo =
      Repo.all(Todo, prefix: tenant.schema_name)
      |> Enum.find(&(&1.starts_at != nil))

    assert todo, "Expected an appointment-type todo in fixtures"

    assert :ok =
             perform_job(AppointmentReminderWorker, %{
               "todo_id" => todo.id,
               "tenant_schema" => tenant.schema_name,
               "channel" => "http",
               "user_id" => user_id,
               "subject" => todo.subject
             })

    assert_enqueued(
      worker: CrmReactor.Workers.WebhookWorker,
      args: %{"payload" => %{"type" => "reminder"}}
    )
  end

  test "returns :ok for telegram channel with no bot configured", %{
    tenant: tenant,
    user_id: user_id
  } do
    original = Application.get_env(:crm_reactor, :telegram_bot)
    Application.put_env(:crm_reactor, :telegram_bot, nil)
    on_exit(fn -> Application.put_env(:crm_reactor, :telegram_bot, original) end)

    todo =
      Repo.all(Todo, prefix: tenant.schema_name)
      |> Enum.find(&(&1.starts_at != nil))

    assert :ok =
             perform_job(AppointmentReminderWorker, %{
               "todo_id" => todo.id,
               "tenant_schema" => tenant.schema_name,
               "channel" => "telegram",
               "user_id" => user_id,
               "subject" => todo.subject
             })
  end
end
