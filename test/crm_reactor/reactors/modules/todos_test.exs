defmodule CrmReactor.Reactors.Modules.TodosTest do
  @moduledoc """
  Unit tests for the Todos module covering:
    - contact_id linking on create
    - list format with contact names
    - user isolation (users in the same tenant cannot see each other's todos)
    - tenant separation (two tenants, each with their own data)
  """
  use CrmReactor.DataCase

  alias CrmReactor.CRM.{Contact, ExecutionLog, Todo}
  alias CrmReactor.Reactors.Modules.Todos
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Provisioner

  import Ecto.Query

  setup do
    # ── Tenant alfa: 2 users ─────────────────────────────────────────────
    tid_alfa = "todos_alfa_#{System.unique_integer([:positive])}"
    user_1 = "todos_u1_#{System.unique_integer([:positive])}"
    user_2 = "todos_u2_#{System.unique_integer([:positive])}"

    {:ok, tenant_alfa} = Provisioner.provision(tid_alfa, "Alfa Corp", user_1)
    schema = tenant_alfa.schema_name

    Repo.query!(
      "INSERT INTO global_registry.user_mappings (user_identifier, tenant_id) VALUES ($1, $2)",
      [user_2, tid_alfa]
    )

    # ── Tenant beta: 1 user ──────────────────────────────────────────────
    tid_beta = "todos_beta_#{System.unique_integer([:positive])}"
    user_beta = "todos_ubeta_#{System.unique_integer([:positive])}"

    {:ok, tenant_beta} = Provisioner.provision(tid_beta, "Beta Corp", user_beta)
    schema_beta = tenant_beta.schema_name

    # ── Contacts ─────────────────────────────────────────────────────────
    marie =
      %Contact{}
      |> Contact.changeset(%{first_name: "Marie", last_name: "Dupont"})
      |> Repo.insert!(prefix: schema)

    jean =
      %Contact{}
      |> Contact.changeset(%{first_name: "Jean", last_name: "Martin"})
      |> Repo.insert!(prefix: schema)

    # Same name in beta — must never bleed into alfa queries
    beta_marie =
      %Contact{}
      |> Contact.changeset(%{first_name: "Marie", last_name: "Dupont"})
      |> Repo.insert!(prefix: schema_beta)

    # ── Todos ─────────────────────────────────────────────────────────────
    tomorrow = Date.add(Date.utc_today(), 1)
    next_week = Date.add(Date.utc_today(), 7)

    # user_1: one todo linked to Marie, one unlinked
    Repo.query!(
      "INSERT INTO #{schema}.todos (subject, due_date, created_by, contact_id) VALUES ($1, $2, $3, $4)",
      ["Appeler Marie", tomorrow, user_1, marie.id]
    )

    Repo.query!(
      "INSERT INTO #{schema}.todos (subject, due_date, created_by) VALUES ($1, $2, $3)",
      ["Préparer devis", next_week, user_1]
    )

    # user_2: one unlinked todo
    Repo.query!(
      "INSERT INTO #{schema}.todos (subject, due_date, created_by) VALUES ($1, $2, $3)",
      ["Rappeler client", tomorrow, user_2]
    )

    # user_beta: one todo in the separate tenant
    Repo.query!(
      "INSERT INTO #{schema_beta}.todos (subject, due_date, created_by) VALUES ($1, $2, $3)",
      ["Tâche beta", tomorrow, user_beta]
    )

    on_exit(fn ->
      Provisioner.drop_tenant(tenant_alfa)
      Provisioner.drop_tenant(tenant_beta)
    end)

    %{
      schema: schema,
      schema_beta: schema_beta,
      user_1: user_1,
      user_2: user_2,
      user_beta: user_beta,
      marie: marie,
      jean: jean,
      beta_marie: beta_marie
    }
  end

  # ── Contact linking on create ─────────────────────────────────────────

  describe "contact linking on create" do
    test "unique contact_name resolves to contact_id", %{
      schema: schema,
      user_1: user,
      marie: marie
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "create",
          params: %{"subject" => "Relancer Marie", "contact_name" => "Marie Dupont"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.action == "create"
      assert result.output =~ "créée"

      todo = Repo.one!(from(t in Todo, where: t.subject == "Relancer Marie"), prefix: schema)
      assert todo.contact_id == marie.id
    end

    test "ambiguous contact_name (multiple matches) → contact_id nil, no crash", %{
      schema: schema,
      user_1: user
    } do
      # Add a second "Marie" so the name is ambiguous
      %Contact{}
      |> Contact.changeset(%{first_name: "Marie", last_name: "Durand"})
      |> Repo.insert!(prefix: schema)

      {:ok, result} =
        Todos.execute(%{
          action: "create",
          params: %{"subject" => "Tâche ambig", "contact_name" => "Marie"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.action == "create"

      todo = Repo.one!(from(t in Todo, where: t.subject == "Tâche ambig"), prefix: schema)
      assert is_nil(todo.contact_id)
    end

    test "unknown contact_name → contact_id nil, no crash", %{schema: schema, user_1: user} do
      {:ok, result} =
        Todos.execute(%{
          action: "create",
          params: %{"subject" => "Tâche inconnue", "contact_name" => "Inconnu Inexistant"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.action == "create"

      todo = Repo.one!(from(t in Todo, where: t.subject == "Tâche inconnue"), prefix: schema)
      assert is_nil(todo.contact_id)
    end

    test "no contact_name → contact_id nil", %{schema: schema, user_1: user} do
      {:ok, result} =
        Todos.execute(%{
          action: "create",
          params: %{"subject" => "Tâche libre"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.action == "create"

      todo = Repo.one!(from(t in Todo, where: t.subject == "Tâche libre"), prefix: schema)
      assert is_nil(todo.contact_id)
    end
  end

  # ── List formatting ───────────────────────────────────────────────────

  describe "list" do
    test "displays [Contact Name] next to linked todos", %{schema: schema, user_1: user} do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Appeler Marie"
      assert result.output =~ "[Marie Dupont]"
    end

    test "unlinked todos show no contact bracket", %{schema: schema, user_1: user} do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{},
          tenant_schema: schema,
          user_id: user
        })

      devis_line =
        result.output
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "Préparer devis"))

      assert devis_line
      refute String.contains?(devis_line, "[")
    end

    test "filtered by contact_name returns only that contact's todos", %{
      schema: schema,
      user_1: user
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"contact_name" => "Marie Dupont"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Appeler Marie"
      refute result.output =~ "Préparer devis"
    end

    test "contact_name linked via contact_id is found even if not in subject", %{
      schema: schema,
      user_1: user,
      marie: marie
    } do
      # Insert a todo linked to Marie but with a generic subject (no 'Marie' in text)
      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, due_date, created_by, contact_id) VALUES ($1, $2, $3, $4)",
        ["Rappel client", Date.add(Date.utc_today(), 1), user, marie.id]
      )

      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"contact_name" => "Marie Dupont"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Rappel client"
    end

    test "ambiguous contact_name returns disambiguation message, not random todos", %{
      schema: schema,
      user_1: user
    } do
      # Add a second Marie so the name is ambiguous
      %Contact{}
      |> Contact.changeset(%{first_name: "Marie", last_name: "Durand"})
      |> Repo.insert!(prefix: schema)

      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"contact_name" => "Marie"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Plusieurs contacts"
      assert result.output =~ "Marie Dupont"
      assert result.output =~ "Marie Durand"
      assert result.output =~ "Précisez"
    end

    test "unknown contact_name falls back to subject text search", %{
      schema: schema,
      user_1: user
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"contact_name" => "Inconnu Inexistant"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output == "Aucune tâche en cours."
    end
  end

  # ── Date filtering ────────────────────────────────────────────────────

  describe "date filtering" do
    setup %{schema: schema, user_1: user_1} do
      yesterday = Date.add(Date.utc_today(), -1)

      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, due_date, created_by) VALUES ($1, $2, $3)",
        ["Tâche passée", yesterday, user_1]
      )

      :ok
    end

    test "no date filter returns today and future todos, not past", %{
      schema: schema,
      user_1: user
    } do
      {:ok, result} =
        Todos.execute(%{action: "list", params: %{}, tenant_schema: schema, user_id: user})

      refute result.output =~ "Tâche passée"
      assert result.output =~ "Appeler Marie"
      assert result.output =~ "Préparer devis"
    end

    test "due_before (future): shows today through that date, not past", %{
      schema: schema,
      user_1: user
    } do
      tomorrow = Date.add(Date.utc_today(), 1) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"due_before" => tomorrow},
          tenant_schema: schema,
          user_id: user
        })

      refute result.output =~ "Tâche passée"
      assert result.output =~ "Appeler Marie"
      refute result.output =~ "Préparer devis"
    end

    test "due_before in the past: only past todos", %{schema: schema, user_1: user} do
      yesterday = Date.add(Date.utc_today(), -1) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"due_before" => yesterday},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Tâche passée"
      refute result.output =~ "Appeler Marie"
      refute result.output =~ "Préparer devis"
    end

    test "due_after: only tasks on or after that date", %{schema: schema, user_1: user} do
      tomorrow = Date.add(Date.utc_today(), 1) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"due_after" => tomorrow},
          tenant_schema: schema,
          user_id: user
        })

      refute result.output =~ "Tâche passée"
      assert result.output =~ "Appeler Marie"
      assert result.output =~ "Préparer devis"
    end

    test "due_on: only tasks exactly on that date", %{schema: schema, user_1: user} do
      tomorrow = Date.add(Date.utc_today(), 1) |> Date.to_iso8601()

      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"due_on" => tomorrow},
          tenant_schema: schema,
          user_id: user
        })

      refute result.output =~ "Tâche passée"
      assert result.output =~ "Appeler Marie"
      refute result.output =~ "Préparer devis"
    end

    test "invalid date string is ignored — falls back to default filter", %{
      schema: schema,
      user_1: user
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{"due_on" => "not-a-date"},
          tenant_schema: schema,
          user_id: user
        })

      # Behaves as if no date filter was given
      assert result.action == "list"
      assert result.output =~ "Appeler Marie"
    end
  end

  # ── User isolation ────────────────────────────────────────────────────

  describe "user isolation" do
    test "user_2 list sees only user_2's todos, not user_1's", %{schema: schema, user_2: user_2} do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{},
          tenant_schema: schema,
          user_id: user_2
        })

      assert result.output =~ "Rappeler client"
      refute result.output =~ "Appeler Marie"
      refute result.output =~ "Préparer devis"
    end

    test "user with no todos gets empty message", %{schema: schema} do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{},
          tenant_schema: schema,
          user_id: "ghost_user_#{System.unique_integer([:positive])}"
        })

      assert result.output == "Aucune tâche en cours."
    end

    test "user_2 cannot complete user_1's todo", %{schema: schema, user_2: user_2} do
      {:ok, result} =
        Todos.execute(%{
          action: "complete",
          params: %{"subject" => "Appeler Marie"},
          tenant_schema: schema,
          user_id: user_2
        })

      assert result.output =~ "Aucune tâche trouvée"

      # Verify user_1's todo is still not done
      todo = Repo.one!(from(t in Todo, where: t.subject == "Appeler Marie"), prefix: schema)
      assert todo.done == false
    end
  end

  # ── Tenant separation ─────────────────────────────────────────────────

  describe "tenant separation" do
    test "beta user sees only beta todos, not alfa's", %{
      schema_beta: schema_beta,
      user_beta: user_beta
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "list",
          params: %{},
          tenant_schema: schema_beta,
          user_id: user_beta
        })

      assert result.output =~ "Tâche beta"
      refute result.output =~ "Appeler Marie"
      refute result.output =~ "Préparer devis"
    end

    test "contact resolution stays within the tenant schema", %{
      schema_beta: schema_beta,
      user_beta: user_beta,
      beta_marie: beta_marie
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "create",
          params: %{"subject" => "Test contact beta", "contact_name" => "Marie Dupont"},
          tenant_schema: schema_beta,
          user_id: user_beta
        })

      assert result.action == "create"

      todo =
        Repo.one!(from(t in Todo, where: t.subject == "Test contact beta"), prefix: schema_beta)

      # contact_id must point to beta's Marie, not alfa's
      assert todo.contact_id == beta_marie.id
    end
  end

  # ── Complete ──────────────────────────────────────────────────────────

  describe "complete" do
    test "marks a matching todo as done", %{schema: schema, user_1: user} do
      {:ok, result} =
        Todos.execute(%{
          action: "complete",
          params: %{"subject" => "Appeler Marie"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.action == "complete"
      assert result.output =~ "complétée"

      todo = Repo.one!(from(t in Todo, where: t.subject == "Appeler Marie"), prefix: schema)
      assert todo.done == true
    end

    test "no match returns not found message", %{schema: schema, user_1: user} do
      {:ok, result} =
        Todos.execute(%{
          action: "complete",
          params: %{"subject" => "Tâche inexistante"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Aucune tâche trouvée"
    end

    test "contact_name resolves to id: todo found via contact_id even without name in subject", %{
      schema: schema,
      user_1: user,
      marie: marie
    } do
      # Todo with a generic subject — no "Marie" text, but linked to Marie by contact_id
      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, due_date, created_by, contact_id) VALUES ($1, $2, $3, $4)",
        ["Réunion importante", Date.add(Date.utc_today(), 1), user, marie.id]
      )

      {:ok, result} =
        Todos.execute(%{
          action: "complete",
          params: %{"subject" => "Réunion importante", "contact_name" => "Marie Dupont"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.action == "complete"
      assert result.output =~ "complétée"
    end

    test "contact_name not in DB falls back to subject ilike match", %{
      schema: schema,
      user_1: user
    } do
      {:ok, result} =
        Todos.execute(%{
          action: "complete",
          params: %{"subject" => "Inconnu", "contact_name" => "Inconnu Inexistant"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Aucune tâche trouvée"
    end

    test "multiple matches returns ambiguous message", %{schema: schema, user_1: user} do
      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, due_date, created_by) VALUES ($1, $2, $3), ($4, $5, $6)",
        [
          "Rappel fournisseur A",
          Date.add(Date.utc_today(), 1),
          user,
          "Rappel fournisseur B",
          Date.add(Date.utc_today(), 1),
          user
        ]
      )

      {:ok, result} =
        Todos.execute(%{
          action: "complete",
          params: %{"subject" => "Rappel fournisseur"},
          tenant_schema: schema,
          user_id: user
        })

      assert result.output =~ "Plusieurs tâches"
    end
  end

  # ── Update / Delete (pending) ─────────────────────────────────────────

  describe "update and delete" do
    setup %{schema: schema, user_1: user} do
      log =
        %ExecutionLog{}
        |> ExecutionLog.create_changeset(%{
          triggered_by: user,
          channel: "http",
          raw_input: "test"
        })
        |> Repo.insert!(prefix: schema)

      %{log_id: log.id}
    end

    test "update creates a pending confirmation", %{schema: schema, user_1: user, log_id: log_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "update",
          params: %{"subject" => "Appeler Marie", "due_date" => "2026-12-01"},
          tenant_schema: schema,
          user_id: user,
          log_id: log_id
        })

      assert result.action == "pending"
      assert result.pending_id
      assert result.output =~ "Confirmez"
    end

    test "delete creates a pending confirmation", %{schema: schema, user_1: user, log_id: log_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "delete",
          params: %{"subject" => "Appeler Marie"},
          tenant_schema: schema,
          user_id: user,
          log_id: log_id
        })

      assert result.action == "pending"
      assert result.pending_id
    end

    test "update with no match returns not found", %{schema: schema, user_1: user, log_id: log_id} do
      {:ok, result} =
        Todos.execute(%{
          action: "update",
          params: %{"subject" => "Inexistant XYZ"},
          tenant_schema: schema,
          user_id: user,
          log_id: log_id
        })

      assert result.output =~ "Aucune tâche"
      assert result.action == "update"
    end

    test "delete with multiple matches returns ambiguous", %{
      schema: schema,
      user_1: user,
      log_id: log_id
    } do
      Repo.query!(
        "INSERT INTO #{schema}.todos (subject, due_date, created_by) VALUES ($1, $2, $3), ($4, $5, $6)",
        [
          "Réunion client A",
          Date.add(Date.utc_today(), 1),
          user,
          "Réunion client B",
          Date.add(Date.utc_today(), 1),
          user
        ]
      )

      {:ok, result} =
        Todos.execute(%{
          action: "delete",
          params: %{"subject" => "Réunion client"},
          tenant_schema: schema,
          user_id: user,
          log_id: log_id
        })

      assert result.output =~ "Plusieurs tâches"
    end
  end

  # ── NL2SQL routing ────────────────────────────────────────────────────

  setup :stub_nl2sql_adapter

  defp stub_nl2sql_adapter(_ctx) do
    prev = Application.get_env(:crm_reactor, :nl2sql_adapter)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:crm_reactor, :nl2sql_adapter, prev),
        else: Application.delete_env(:crm_reactor, :nl2sql_adapter)
    end)

    :ok
  end

  test "list with nl2sql routing returns todos for user", %{schema: schema, user_1: user_id} do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:ok, %{"filters" => [], "sort_by" => nil, "sort_dir" => "asc"}}
    end)

    {:ok, result} =
      Todos.execute(%{
        action: "list",
        routing_path: "nl2sql",
        raw_text: "mes todos",
        params: %{},
        tenant_schema: schema,
        user_id: user_id
      })

    assert result.action == "list"
    assert result.data["count"] == 2
  end

  test "list with nl2sql routing falls back to deterministic on LLM error", %{
    schema: schema,
    user_1: user_id
  } do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:error, "simulated LLM error"}
    end)

    {:ok, result} =
      Todos.execute(%{
        action: "list",
        routing_path: "nl2sql",
        raw_text: "mes todos",
        params: %{},
        tenant_schema: schema,
        user_id: user_id
      })

    assert result.action == "list"
  end

  # ── Unsupported action ────────────────────────────────────────────────

  test "unsupported action returns error message" do
    {:ok, result} = Todos.execute(%{action: "export"})
    assert result.output =~ "non supportée"
  end
end
