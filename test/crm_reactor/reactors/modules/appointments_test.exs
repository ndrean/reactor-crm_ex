defmodule CrmReactor.Reactors.Modules.AppointmentsTest do
  @moduledoc "Tests for appointment actions in the Todos module."
  use CrmReactor.DataCase

  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Reactors.Modules.{Mutations, Todos}
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Provisioner

  import Ecto.Query

  setup do
    tid = "appt_#{System.unique_integer([:positive])}"
    user_id = "appt_user_#{System.unique_integer([:positive])}@test.com"
    {:ok, tenant} = Provisioner.provision(tid, "Appt Corp", user_id)
    schema = tenant.schema_name

    marie =
      %Contact{}
      |> Contact.changeset(%{first_name: "Marie", last_name: "Dupont"})
      |> Repo.insert!(prefix: schema)

    # Seed an existing appointment
    tomorrow = Date.add(Date.utc_today(), 1)
    starts_at = DateTime.new!(tomorrow, ~T[14:00:00], "Etc/UTC")
    ends_at = DateTime.add(starts_at, 3600, :second)

    Repo.query!(
      """
      INSERT INTO #{schema}.todos
        (subject, created_by, starts_at, ends_at, location, reminder_minutes, contact_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      ["Réunion Marie", user_id, starts_at, ends_at, "Bureau", 30, marie.id]
    )

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    %{schema: schema, user_id: user_id, marie: marie, starts_at: starts_at}
  end

  # ── Create ─────────────────────────────────────────────────────────────

  describe "create_appointment" do
    test "creates an appointment with starts_at and schedules reminder", %{
      schema: schema,
      user_id: user_id
    } do
      next_week = Date.add(Date.utc_today(), 7) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "create_appointment",
          params: %{
            "subject" => "Déjeuner client",
            "date" => next_week,
            "time" => "12:30",
            "location" => "Restaurant"
          },
          tenant_schema: schema,
          user_id: user_id,
          channel: :http
        })

      assert result.action == "create_appointment"
      assert result.output =~ "Rendez-vous créé"
      assert result.output =~ "Déjeuner client"
      assert result.data["todo_id"]
      assert result.data["starts_at"]
      assert result.data["reminder_job_id"]

      # Verify DB
      todo = Repo.get!(Todo, result.data["todo_id"], prefix: schema)
      assert todo.starts_at
      assert todo.ends_at
      assert todo.location == "Restaurant"
      assert todo.reminder_minutes == 30
      assert todo.reminder_job_id == result.data["reminder_job_id"]
    end

    test "create with custom duration and reminder", %{schema: schema, user_id: user_id} do
      next_week = Date.add(Date.utc_today(), 7) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "create_appointment",
          params: %{
            "subject" => "Conf call",
            "date" => next_week,
            "time" => "09:00",
            "duration" => "90",
            "reminder_minutes" => "15"
          },
          tenant_schema: schema,
          user_id: user_id,
          channel: :http
        })

      assert result.action == "create_appointment"
      todo = Repo.get!(Todo, result.data["todo_id"], prefix: schema)
      # 90 minutes duration
      assert DateTime.diff(todo.ends_at, todo.starts_at) == 90 * 60
      assert todo.reminder_minutes == 15
    end

    test "create with contact_name links contact_id", %{
      schema: schema,
      user_id: user_id,
      marie: marie
    } do
      next_week = Date.add(Date.utc_today(), 7) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "create_appointment",
          params: %{
            "subject" => "RDV Marie",
            "date" => next_week,
            "time" => "10:00",
            "contact_name" => "Marie Dupont"
          },
          tenant_schema: schema,
          user_id: user_id,
          channel: :http
        })

      assert result.action == "create_appointment"
      todo = Repo.get!(Todo, result.data["todo_id"], prefix: schema)
      assert todo.contact_id == marie.id
    end

    test "create with invalid date returns error", %{schema: schema, user_id: user_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "create_appointment",
          params: %{"subject" => "Test", "date" => "not-a-date", "time" => "14:00"},
          tenant_schema: schema,
          user_id: user_id,
          channel: :http
        })

      assert result.output =~ "Erreur de date/heure"
    end

    test "create with missing date/time returns error", %{schema: schema, user_id: user_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "create_appointment",
          params: %{"subject" => "Test"},
          tenant_schema: schema,
          user_id: user_id,
          channel: :http
        })

      assert result.output =~ "date et heure sont obligatoires"
    end

    test "create with past date does not schedule reminder (reminder_job_id is nil)", %{
      schema: schema,
      user_id: user_id
    } do
      yesterday = Date.add(Date.utc_today(), -1) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "create_appointment",
          params: %{
            "subject" => "Passé",
            "date" => yesterday,
            "time" => "09:00"
          },
          tenant_schema: schema,
          user_id: user_id,
          channel: :http
        })

      assert result.action == "create_appointment"
      assert result.data["reminder_job_id"] == nil
    end
  end

  # ── List ───────────────────────────────────────────────────────────────

  describe "list_appointments" do
    test "lists upcoming appointments (not regular todos)", %{
      schema: schema,
      user_id: user_id
    } do
      # Add a regular todo (no starts_at) — should NOT appear
      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, created_by, due_date) VALUES ($1, $2, $3)",
        ["Tâche simple", user_id, Date.add(Date.utc_today(), 1)]
      )

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.action == "list_appointments"
      assert result.output =~ "Réunion Marie"
      assert result.output =~ "Bureau"
      refute result.output =~ "Tâche simple"
      assert result.data["count"] == 1
    end

    test "list filtered by contact_name", %{schema: schema, user_id: user_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"contact_name" => "Marie Dupont"},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.output =~ "Réunion Marie"
      assert result.output =~ "[Marie Dupont]"
    end

    test "empty list returns appropriate message", %{schema: schema} do
      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{},
          tenant_schema: schema,
          user_id: "ghost_user"
        })

      assert result.output == "Aucun rendez-vous à venir."
    end

    test "list with period=today filters to today only", %{schema: schema, user_id: user_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"period" => "today"},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] == 0
    end

    test "list with period=week includes this week", %{schema: schema, user_id: user_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"period" => "week"},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] >= 1
    end

    test "list with specific date filter", %{
      schema: schema,
      user_id: user_id,
      starts_at: starts_at
    } do
      date = DateTime.to_date(starts_at) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"date" => date},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] >= 1
      assert result.output =~ "Réunion Marie"
    end

    test "list with due_on filter", %{schema: schema, user_id: user_id, starts_at: starts_at} do
      date = DateTime.to_date(starts_at) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"due_on" => date},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] >= 1
      assert result.output =~ "Réunion Marie"
    end

    test "list with due_on for wrong date returns empty", %{schema: schema, user_id: user_id} do
      wrong_date = Date.add(Date.utc_today(), 10) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"due_on" => wrong_date},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] == 0
    end

    test "list with due_after filter", %{schema: schema, user_id: user_id} do
      today = Date.utc_today() |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"due_after" => today},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] >= 1
    end

    test "list with due_before filter (future)", %{schema: schema, user_id: user_id} do
      next_week = Date.add(Date.utc_today(), 7) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{"due_before" => next_week},
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] >= 1
    end

    test "list with due_before + due_after combined", %{
      schema: schema,
      user_id: user_id,
      starts_at: starts_at
    } do
      date = DateTime.to_date(starts_at)

      {:ok, result} =
        Todos.execute(%{
          action: "list_appointments",
          params: %{
            "due_after" => Date.to_iso8601(date),
            "due_before" => Date.to_iso8601(date)
          },
          tenant_schema: schema,
          user_id: user_id
        })

      assert result.data["count"] >= 1
    end
  end

  # ── Cancel ─────────────────────────────────────────────────────────────

  describe "cancel_appointment" do
    setup %{schema: schema, user_id: user_id} do
      log =
        %ExecutionLog{}
        |> ExecutionLog.create_changeset(%{
          triggered_by: user_id,
          channel: "http",
          raw_input: "annule rdv"
        })
        |> Repo.insert!(prefix: schema)

      %{log_id: log.id}
    end

    test "cancel creates pending confirmation", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "cancel_appointment",
          params: %{"subject" => "Réunion Marie"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.action == "pending"
      assert result.pending_id
      assert result.output =~ "Annuler"
      assert result.output =~ "Réunion Marie"
    end

    test "cancel with no match returns not found", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "cancel_appointment",
          params: %{"subject" => "Inexistant XYZ"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.output =~ "Aucun rendez-vous"
    end
  end

  # ── Reschedule ─────────────────────────────────────────────────────────

  describe "reschedule" do
    setup %{schema: schema, user_id: user_id} do
      log =
        %ExecutionLog{}
        |> ExecutionLog.create_changeset(%{
          triggered_by: user_id,
          channel: "http",
          raw_input: "déplace rdv"
        })
        |> Repo.insert!(prefix: schema)

      %{log_id: log.id}
    end

    test "reschedule creates pending confirmation", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "reschedule",
          params: %{
            "subject" => "Réunion Marie",
            "new_date" => Date.add(Date.utc_today(), 3) |> Date.to_iso8601(),
            "new_time" => "16:00"
          },
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.action == "pending"
      assert result.pending_id
      assert result.output =~ "Reprogrammer"
      assert result.output =~ "Réunion Marie"
    end

    test "reschedule with no match returns not found", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "reschedule",
          params: %{"subject" => "Inexistant"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.output =~ "Aucun rendez-vous"
    end
  end

  # ── Multiple matches ──────────────────────────────────────────────────

  describe "multiple matches" do
    setup %{schema: schema, user_id: user_id} do
      day_after = Date.add(Date.utc_today(), 2)
      starts_at = DateTime.new!(day_after, ~T[10:00:00], "Etc/UTC")
      ends_at = DateTime.add(starts_at, 3600, :second)

      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, created_by, starts_at, ends_at) VALUES ($1, $2, $3, $4)",
        ["Réunion Marie Soir", user_id, starts_at, ends_at]
      )

      Repo.query!(
        "UPDATE #{schema}.todos SET subject = 'Réunion Marie Matin' WHERE subject = 'Réunion Marie' AND starts_at IS NOT NULL",
        []
      )

      log =
        %ExecutionLog{}
        |> ExecutionLog.create_changeset(%{
          triggered_by: user_id,
          channel: "http",
          raw_input: "test"
        })
        |> Repo.insert!(prefix: schema)

      %{log_id: log.id}
    end

    test "cancel with multiple matches returns ambiguity message", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "cancel_appointment",
          params: %{"subject" => "Réunion"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.output =~ "Plusieurs"
    end

    test "reschedule with multiple matches returns ambiguity message", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "reschedule",
          params: %{
            "subject" => "Réunion",
            "new_date" => "2026-08-01",
            "new_time" => "10:00"
          },
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.output =~ "Plusieurs"
    end
  end

  # ── Mutations (confirm flow) ───────────────────────────────────────────

  describe "mutations" do
    setup %{schema: schema, user_id: user_id} do
      log =
        %ExecutionLog{}
        |> ExecutionLog.create_changeset(%{
          triggered_by: user_id,
          channel: "http",
          raw_input: "test"
        })
        |> Repo.insert!(prefix: schema)

      %{log_id: log.id}
    end

    test "cancel confirm sets done=true", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "cancel_appointment",
          params: %{"subject" => "Réunion Marie"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.action == "pending"

      {:ok, confirmed} = Mutations.confirm(result.pending_id, "confirm", user_id)
      assert confirmed.output =~ "annulé"

      appt =
        from(t in Todo, where: t.subject == "Réunion Marie" and not is_nil(t.starts_at))
        |> Repo.one!(prefix: schema)

      assert appt.done == true
    end

    test "reschedule confirm updates starts_at", %{
      schema: schema,
      user_id: user_id,
      log_id: log_id
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "reschedule",
          params: %{
            "subject" => "Réunion Marie",
            "new_date" => Date.add(Date.utc_today(), 5) |> Date.to_iso8601(),
            "new_time" => "09:00"
          },
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })

      assert result.action == "pending"

      {:ok, confirmed} = Mutations.confirm(result.pending_id, "confirm", user_id)
      assert confirmed.output =~ "reprogrammé"

      appt =
        from(t in Todo, where: t.subject == "Réunion Marie" and not is_nil(t.starts_at))
        |> Repo.one!(prefix: schema)

      expected_date = Date.add(Date.utc_today(), 5)
      assert DateTime.to_date(appt.starts_at) == expected_date
    end
  end

  # ── Unsupported action ────────────────────────────────────────────────

  test "unsupported action returns error message" do
    {:ok, result} = Todos.execute(%{action: "export"})
    assert result.output =~ "non supportée"
  end
end
