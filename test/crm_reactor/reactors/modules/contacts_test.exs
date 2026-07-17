defmodule CrmReactor.Reactors.Modules.ContactsTest do
  use CrmReactor.DataCase

  alias CrmReactor.CRM.{Contact, ExecutionLog}
  alias CrmReactor.Reactors.Modules.Contacts
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.Provisioner

  import Ecto.Query

  setup do
    tid = "contacts_mod_#{System.unique_integer([:positive])}"
    user_id = "contacts_u_#{System.unique_integer([:positive])}@test.com"
    {:ok, tenant} = Provisioner.provision(tid, "Test Corp", user_id)
    schema = tenant.schema_name

    marie =
      %Contact{}
      |> Contact.changeset(%{
        first_name: "Marie",
        last_name: "Dupont",
        email: "marie@test.fr",
        phone: "0601020304",
        company_name: "TestCorp"
      })
      |> Repo.insert!(prefix: schema)

    paul =
      %Contact{}
      |> Contact.changeset(%{
        first_name: "Paul",
        last_name: "Martin",
        phone: "0605060708",
        company_name: "OtherCorp"
      })
      |> Repo.insert!(prefix: schema)

    log =
      %ExecutionLog{}
      |> ExecutionLog.create_changeset(%{
        triggered_by: user_id,
        channel: "http",
        raw_input: "test"
      })
      |> Repo.insert!(prefix: schema)

    on_exit(fn -> Provisioner.drop_tenant(tenant) end)

    %{schema: schema, user_id: user_id, marie: marie, paul: paul, log_id: log.id}
  end

  defp ctx(overrides) do
    Map.merge(
      %{routing_path: "deterministic", raw_text: "", user_id: "u", log_id: 0},
      overrides
    )
  end

  # ── Search ────────────────────────────────────────────────────────────

  test "search by name returns matching contacts", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{action: "search", params: %{"search_name" => "Marie"}, tenant_schema: schema})
      )

    assert result.action == "search"
    assert result.output =~ "Marie"
    assert result.data["count"] == 1
  end

  test "search by company returns matching contacts", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{
          action: "search",
          params: %{"search_company" => "OtherCorp"},
          tenant_schema: schema
        })
      )

    assert result.output =~ "Paul"
    assert result.data["count"] == 1
  end

  test "search with no results returns empty message", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{action: "search", params: %{"search_name" => "Fantôme"}, tenant_schema: schema})
      )

    assert result.output =~ "Aucun contact"
  end

  test "search all (empty name) returns all contacts", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{action: "search", params: %{"search_name" => ""}, tenant_schema: schema})
      )

    assert result.data["count"] == 2
  end

  # ── Count ─────────────────────────────────────────────────────────────

  test "count with company filter returns filtered count", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{action: "count", params: %{"filter" => "TestCorp"}, tenant_schema: schema})
      )

    assert result.action == "count"
    assert result.data["count"] == 1
  end

  test "count without filter returns total", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(ctx(%{action: "count", params: %{}, tenant_schema: schema}))

    assert result.data["count"] == 2
  end

  # ── Create ───────────────────────────────────────────────────────────

  test "create with search_name normalizes into first/last name", %{schema: schema} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{action: "create", params: %{"search_name" => "Jean Dupont"}, tenant_schema: schema})
      )

    assert result.action == "create"
    assert result.output =~ "Jean"

    contact = Repo.one!(from(c in Contact, where: c.first_name == "Jean"), prefix: schema)
    assert contact.last_name == "Dupont"
  end

  test "create with duplicate phone returns duplicate message", %{schema: schema, marie: marie} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{
          action: "create",
          params: %{"first_name" => "Autre", "phone" => "0601020304"},
          tenant_schema: schema
        })
      )

    assert result.output =~ "existe déjà"
    assert result.output =~ marie.first_name
  end

  # ── Update / Delete (pending) ─────────────────────────────────────────

  test "update single match creates pending confirmation", %{
    schema: schema,
    user_id: user_id,
    log_id: log_id
  } do
    {:ok, result} =
      Contacts.execute(
        ctx(%{
          action: "update",
          params: %{"search_name" => "Marie Dupont", "first_name" => "Marie-Claire"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })
      )

    assert result.action == "pending"
    assert result.pending_id
    assert result.output =~ "Confirmez"
    assert result.output =~ "Marie"
  end

  test "delete single match creates pending confirmation", %{
    schema: schema,
    user_id: user_id,
    log_id: log_id
  } do
    {:ok, result} =
      Contacts.execute(
        ctx(%{
          action: "delete",
          params: %{"search_name" => "Paul Martin"},
          tenant_schema: schema,
          user_id: user_id,
          log_id: log_id
        })
      )

    assert result.action == "pending"
    assert result.pending_id
  end

  test "update with no match returns not found", %{schema: schema, log_id: log_id} do
    {:ok, result} =
      Contacts.execute(
        ctx(%{
          action: "update",
          params: %{"search_name" => "Fantôme"},
          tenant_schema: schema,
          log_id: log_id
        })
      )

    assert result.output =~ "Aucun contact"
    assert result.action == "update"
  end

  test "update with multiple matches returns list", %{schema: schema, log_id: log_id} do
    %Contact{}
    |> Contact.changeset(%{first_name: "Marie", last_name: "Durand"})
    |> Repo.insert!(prefix: schema)

    {:ok, result} =
      Contacts.execute(
        ctx(%{
          action: "update",
          params: %{"search_name" => "Marie"},
          tenant_schema: schema,
          log_id: log_id
        })
      )

    assert result.output =~ "Plusieurs contacts"
    assert result.action == "update"
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

  test "search with nl2sql routing returns filtered contacts", %{schema: schema} do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:ok, %{"filters" => [], "sort_by" => nil, "sort_dir" => "asc"}}
    end)

    {:ok, result} =
      Contacts.execute(%{
        action: "search",
        routing_path: "nl2sql",
        raw_text: "montre tous les contacts",
        tenant_schema: schema
      })

    assert result.action == "search"
    assert result.data["count"] == 2
  end

  test "search with nl2sql routing falls back to deterministic on LLM error", %{schema: schema} do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:error, "simulated LLM error"}
    end)

    {:ok, result} =
      Contacts.execute(%{
        action: "search",
        routing_path: "nl2sql",
        raw_text: "cherche quelqu'un",
        tenant_schema: schema
      })

    assert result.action == "search"
  end

  test "count with nl2sql routing returns count", %{schema: schema} do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:ok, %{"filters" => [], "sort_by" => nil, "sort_dir" => "asc"}}
    end)

    {:ok, result} =
      Contacts.execute(%{
        action: "count",
        routing_path: "nl2sql",
        raw_text: "combien de contacts",
        tenant_schema: schema
      })

    assert result.action == "count"
    assert result.data["count"] == 2
  end

  test "count with nl2sql routing falls back on LLM error", %{schema: schema} do
    Application.put_env(:crm_reactor, :nl2sql_adapter, fn _p, _t ->
      {:error, "simulated LLM error"}
    end)

    {:ok, result} =
      Contacts.execute(%{
        action: "count",
        routing_path: "nl2sql",
        raw_text: "combien",
        tenant_schema: schema
      })

    assert result.action == "count"
    assert result.data["count"] == 2
  end

  # ── Unsupported action ────────────────────────────────────────────────

  test "unsupported action returns error message" do
    {:ok, result} = Contacts.execute(%{action: "export"})
    assert result.output =~ "non supportée"
  end
end
