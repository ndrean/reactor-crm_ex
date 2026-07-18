defmodule CrmReactor.Reactors.Modules.MutationsTest do
  use CrmReactor.DataCase

  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Reactors.Modules.Mutations
  alias CrmReactor.Repo
  alias CrmReactor.TestFixtures

  import Ecto.Query

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    log =
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: fixture.user_id,
        channel: "http",
        raw_input: "test"
      })
      |> Repo.insert!(prefix: fixture.tenant.schema_name)

    %{fixture: fixture, log: log, schema: fixture.tenant.schema_name, user_id: fixture.user_id}
  end

  defp put_pending(log, schema, module, action, proposed_params) do
    log
    |> ExecutionLog.pending_changeset(%{
      action: action,
      module: module,
      proposed_params: proposed_params
    })
    |> Repo.update!(prefix: schema)
  end

  defp first_contact(schema) do
    Repo.one!(from(c in Contact, limit: 1), prefix: schema)
  end

  defp first_todo(schema, user_id) do
    Repo.one!(from(t in Todo, where: t.created_by == ^user_id, limit: 1), prefix: schema)
  end

  # ── Unknown pending_id ────────────────────────────────────────────────

  test "unknown pending_id returns {:error, :pending_not_found}", %{schema: schema} do
    assert {:error, :pending_not_found} =
             Mutations.confirm_system(Ecto.UUID.generate(), "confirm", schema)
  end

  # ── Reject ────────────────────────────────────────────────────────────

  test "reject cancels the pending action", %{log: log, schema: schema, user_id: user_id} do
    contact = first_contact(schema)
    pending = put_pending(log, schema, "contacts", "delete", %{"contact_id" => contact.id})

    {:ok, result} = Mutations.confirm(pending.pending_id, "reject", user_id)

    assert result.output =~ "annulée"
    assert result.action == "rejected"
    # Contact must still be there
    assert Repo.get!(Contact, contact.id, prefix: schema)
  end

  # ── Contacts: update ──────────────────────────────────────────────────

  test "contacts update confirm modifies the contact", %{log: log, schema: schema} do
    contact = first_contact(schema)

    pending =
      put_pending(log, schema, "contacts", "update", %{
        "contact_id" => contact.id,
        "first_name" => "Marie-Claire"
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)

    assert result.output =~ "modifié"

    updated = Repo.get!(Contact, contact.id, prefix: schema)
    assert updated.first_name == "Marie-Claire"
  end

  # ── Contacts: delete ──────────────────────────────────────────────────

  test "contacts delete confirm removes the contact", %{log: log, schema: schema} do
    contact = first_contact(schema)
    pending = put_pending(log, schema, "contacts", "delete", %{"contact_id" => contact.id})

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)

    assert result.output =~ "supprimé"
    assert Repo.get(Contact, contact.id, prefix: schema) == nil
  end

  # ── Todos: update ─────────────────────────────────────────────────────

  test "todos update confirm applies due_date change", %{
    log: log,
    schema: schema,
    user_id: user_id
  } do
    todo = first_todo(schema, user_id)
    new_date = Date.add(Date.utc_today(), 14) |> Date.to_string()

    pending =
      put_pending(log, schema, "todos", "update", %{
        "todo_id" => todo.id,
        "due_date" => new_date,
        "subject" => todo.subject
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)

    assert result.output =~ "modifiée"

    updated = Repo.get!(Todo, todo.id, prefix: schema)
    assert Date.to_string(updated.due_date) == new_date
  end

  test "todos update confirm renames subject via new_subject", %{
    log: log,
    schema: schema,
    user_id: user_id
  } do
    todo = first_todo(schema, user_id)

    pending =
      put_pending(log, schema, "todos", "update", %{
        "todo_id" => todo.id,
        "new_subject" => "Titre renommé",
        "subject" => todo.subject
      })

    Mutations.confirm_system(pending.pending_id, "confirm", schema)

    updated = Repo.get!(Todo, todo.id, prefix: schema)
    assert updated.subject == "Titre renommé"
  end

  # ── Todos: delete ─────────────────────────────────────────────────────

  test "todos delete confirm removes the todo", %{log: log, schema: schema, user_id: user_id} do
    todo = first_todo(schema, user_id)
    pending = put_pending(log, schema, "todos", "delete", %{"todo_id" => todo.id})

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)

    assert result.output =~ "supprimée"
    assert Repo.get(Todo, todo.id, prefix: schema) == nil
  end

  # ── Invalid decision ──────────────────────────────────────────────────

  test "invalid decision returns {:error, :invalid_decision}", %{log: log, schema: schema} do
    contact = first_contact(schema)
    pending = put_pending(log, schema, "contacts", "delete", %{"contact_id" => contact.id})

    assert {:error, :invalid_decision} =
             Mutations.confirm_system(pending.pending_id, "maybe", schema)
  end

  # ── Fan-out confirm ───────────────────────────────────────────────────

  test "fanout confirm executes N operations", %{log: log, schema: schema} do
    items = ["Alice Martin", "Bob Dupont"]

    pending =
      put_pending(log, schema, "contacts", "create", %{
        "type" => "fanout",
        "workflow" => "contacts",
        "action" => "create",
        "items" => items,
        "map_param" => "search_name",
        "params" => %{},
        "routing_path" => "deterministic"
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)

    assert result.action == "create"
    assert result.output =~ "opération"
  end

  # ── execute_mutation default clause ──────────────────────────────────

  test "unsupported module/action returns non-supportée message", %{log: log, schema: schema} do
    pending = put_pending(log, schema, "help", "export", %{})

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)

    assert result.output =~ "non supportée"
  end

  # ── provide_export_email with valid address ───────────────────────────

  test "export_email pending with valid address completes export", %{
    log: log,
    schema: schema
  } do
    pending =
      put_pending(log, schema, "data", "dump", %{
        "type" => "export_email"
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "admin@example.fr", schema)

    assert result.output =~ "email" or result.output =~ "envoyées"
    assert result.action == "dump"
  end

  # ── Fanout with unknown module ──────────────────────────────────────────

  test "fanout with unknown module returns 'Module inconnu'", %{log: log, schema: schema} do
    pending =
      put_pending(log, schema, "contacts", "create", %{
        "type" => "fanout",
        "workflow" => "nonexistent_module",
        "action" => "create",
        "items" => ["item1"],
        "map_param" => "name",
        "params" => %{},
        "routing_path" => "deterministic"
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)
    assert result.output =~ "Module inconnu"
  end

  # ── Appointments cancel with nil reminder_job_id ────────────────────────

  test "appointments cancel works when reminder_job_id is nil", %{
    log: log,
    schema: schema,
    user_id: user_id
  } do
    # Insert a todo with starts_at but no reminder_job_id
    tomorrow = Date.add(Date.utc_today(), 1)
    starts_at = DateTime.new!(tomorrow, ~T[10:00:00], "Etc/UTC")
    ends_at = DateTime.add(starts_at, 3600, :second)

    {:ok, %{rows: [[todo_id]]}} =
      Repo.query(
        "INSERT INTO #{schema}.todos (subject, created_by, starts_at, ends_at) VALUES ($1, $2, $3, $4) RETURNING id",
        ["RDV sans rappel", user_id, starts_at, ends_at]
      )

    pending =
      put_pending(log, schema, "todos", "cancel_appointment", %{
        "todo_id" => todo_id
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)
    assert result.output =~ "annulé"
  end

  # ── Reschedule with invalid date ────────────────────────────────────────

  test "appointments reschedule with invalid date returns error", %{
    log: log,
    schema: schema,
    user_id: user_id
  } do
    todo = first_todo(schema, user_id)

    pending =
      put_pending(log, schema, "todos", "reschedule", %{
        "todo_id" => todo.id,
        "new_date" => "not-a-date",
        "new_time" => "bad"
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)
    assert result.output =~ "invalide"
  end

  # ── valid_email? edge cases ─────────────────────────────────────────────

  test "export_email with missing @ returns invalid_email", %{log: log, schema: schema} do
    pending =
      put_pending(log, schema, "data", "dump", %{
        "type" => "export_email"
      })

    assert {:error, :invalid_email} =
             Mutations.confirm_system(pending.pending_id, "not-an-email", schema)
  end

  test "export_email with whitespace returns invalid_email", %{log: log, schema: schema} do
    pending =
      put_pending(log, schema, "data", "dump", %{
        "type" => "export_email"
      })

    assert {:error, :invalid_email} =
             Mutations.confirm_system(pending.pending_id, "bad @email .com", schema)
  end

  # ── Expenses: delete ────────────────────────────────────────────────────

  test "expenses delete confirm removes the expense", %{
    log: log,
    schema: schema,
    user_id: user_id
  } do
    alias CrmReactor.CRM.Expense

    {:ok, expense} =
      %Expense{}
      |> Expense.changeset(%{
        description: "Taxi",
        amount: Decimal.new("25.50"),
        expense_date: Date.utc_today(),
        created_by: user_id
      })
      |> Repo.insert(prefix: schema)

    pending =
      put_pending(log, schema, "expenses", "delete", %{"expense_id" => expense.id})

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)
    assert result.output =~ "supprimée"
    assert Repo.get(Expense, expense.id, prefix: schema) == nil
  end

  # ── Reschedule confirm with valid date ──────────────────────────────────

  test "appointments reschedule confirm with valid date updates starts_at", %{
    log: log,
    schema: schema,
    user_id: user_id
  } do
    tomorrow = Date.add(Date.utc_today(), 1)
    starts_at = DateTime.new!(tomorrow, ~T[10:00:00], "Etc/UTC")
    ends_at = DateTime.add(starts_at, 3600, :second)

    {:ok, %{rows: [[todo_id]]}} =
      Repo.query(
        "INSERT INTO #{schema}.todos (subject, created_by, starts_at, ends_at) VALUES ($1, $2, $3, $4) RETURNING id",
        ["RDV reschedule", user_id, starts_at, ends_at]
      )

    new_date = Date.add(Date.utc_today(), 7) |> Date.to_iso8601()

    pending =
      put_pending(log, schema, "todos", "reschedule", %{
        "todo_id" => todo_id,
        "new_date" => new_date,
        "new_time" => "15:00"
      })

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)
    assert result.output =~ "reprogrammé"

    updated = Repo.get!(Todo, todo_id, prefix: schema)
    assert DateTime.to_date(updated.starts_at) == Date.add(Date.utc_today(), 7)
  end

  # ── confirm_system/3 ────────────────────────────────────────────────────

  test "confirm_system/3 confirms without user authorization", %{
    log: log,
    schema: schema
  } do
    contact = first_contact(schema)
    pending = put_pending(log, schema, "contacts", "delete", %{"contact_id" => contact.id})

    {:ok, result} = Mutations.confirm_system(pending.pending_id, "confirm", schema)
    assert result.output =~ "supprimé"
    assert Repo.get(Contact, contact.id, prefix: schema) == nil
  end

  test "confirm_system/3 returns error for unknown pending_id", %{schema: schema} do
    assert {:error, :pending_not_found} =
             Mutations.confirm_system(Ecto.UUID.generate(), "confirm", schema)
  end
end
