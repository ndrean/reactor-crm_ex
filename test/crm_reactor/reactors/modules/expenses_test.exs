defmodule CrmReactor.Reactors.Modules.ExpensesTest do
  use CrmReactor.DataCase, async: false

  alias CrmReactor.CRM.Expense
  alias CrmReactor.Reactors.Modules.Expenses
  alias CrmReactor.Repo
  alias CrmReactor.TestFixtures

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    schema = fixture.tenant.schema_name

    # Insert an execution log for pending operations
    Repo.query!(
      "INSERT INTO #{schema}.execution_logs (id, triggered_by, channel, raw_input, status) VALUES ($1, $2, $3, $4, $5)",
      [9999, fixture.user_id, "http", "test", "processing"]
    )

    Map.put(fixture, :schema, schema)
  end

  defp base_ctx(fixture, action, params \\ %{}) do
    %{
      action: action,
      params: params,
      routing_path: "deterministic",
      raw_text: "",
      tenant_schema: fixture.schema,
      company_name: "Test Corp",
      admin_email: nil,
      channel: :http,
      user_id: fixture.user_id,
      log_id: 9999
    }
  end

  describe "submit" do
    test "creates expense with amount, date, category", fixture do
      ctx =
        base_ctx(fixture, "submit", %{
          "amount" => "45.50",
          "date" => Date.utc_today() |> Date.to_iso8601(),
          "category" => "restaurant",
          "description" => "Déjeuner client"
        })

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.action == "submit"
      assert result.output =~ "45.50"
      assert result.data["expense_id"]
      assert result.data["category"] == "restaurant"
    end

    test "defaults date to today when missing", fixture do
      ctx = base_ctx(fixture, "submit", %{"amount" => "20", "description" => "Café"})

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.action == "submit"

      expense = Repo.get!(Expense, result.data["expense_id"], prefix: fixture.schema)
      assert expense.expense_date == Date.utc_today()
    end

    test "normalizes comma decimal separator", fixture do
      ctx =
        base_ctx(fixture, "submit", %{
          "amount" => "12,75",
          "date" => Date.utc_today() |> Date.to_iso8601()
        })

      assert {:ok, result} = Expenses.execute(ctx)
      expense = Repo.get!(Expense, result.data["expense_id"], prefix: fixture.schema)
      assert Decimal.equal?(expense.amount, Decimal.new("12.75"))
    end

    test "unknown category defaults to autre", fixture do
      ctx =
        base_ctx(fixture, "submit", %{
          "amount" => "30",
          "date" => Date.utc_today() |> Date.to_iso8601(),
          "category" => "unknown_cat"
        })

      assert {:ok, result} = Expenses.execute(ctx)
      expense = Repo.get!(Expense, result.data["expense_id"], prefix: fixture.schema)
      assert expense.category == "autre"
    end

    test "stores attachment_key when present", fixture do
      ctx =
        base_ctx(fixture, "submit", %{
          "amount" => "55",
          "date" => Date.utc_today() |> Date.to_iso8601(),
          "_attachment_key" => "uploads/test/receipt.jpg"
        })

      assert {:ok, result} = Expenses.execute(ctx)
      expense = Repo.get!(Expense, result.data["expense_id"], prefix: fixture.schema)
      assert expense.attachment_key == "uploads/test/receipt.jpg"
    end

    test "links contact_id when contact_name matches", fixture do
      ctx =
        base_ctx(fixture, "submit", %{
          "amount" => "60",
          "date" => Date.utc_today() |> Date.to_iso8601(),
          "contact_name" => "Marie Dupont"
        })

      assert {:ok, result} = Expenses.execute(ctx)
      expense = Repo.get!(Expense, result.data["expense_id"], prefix: fixture.schema)
      assert expense.contact_id != nil
    end
  end

  describe "list" do
    test "returns seeded expense", fixture do
      ctx = base_ctx(fixture, "list")

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.action == "list"
      assert result.data["count"] >= 1
      assert result.output =~ "42.50"
    end

    test "filters by category", fixture do
      ctx = base_ctx(fixture, "list", %{"category" => "transport"})

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.data["count"] == 0
    end

    test "returns empty message when no expenses match", fixture do
      ctx = base_ctx(fixture, "list", %{"category" => "transport"})

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.output == "Aucune note de frais."
    end
  end

  describe "delete" do
    test "pending flow for matching expense", fixture do
      ctx = base_ctx(fixture, "delete", %{"description" => "Déjeuner équipe"})

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.action == "pending"
      assert result.pending_id
      assert result.output =~ "Confirmez-vous la suppression"
    end

    test "returns not found when no match", fixture do
      ctx = base_ctx(fixture, "delete", %{"description" => "inexistant"})

      assert {:ok, result} = Expenses.execute(ctx)
      assert result.output =~ "Aucune note de frais trouvée"
    end
  end

  describe "user isolation" do
    test "user cannot see another user's expenses", fixture do
      # Insert expense for a different user
      Repo.query!(
        "INSERT INTO #{fixture.schema}.expenses (amount, expense_date, description, created_by) VALUES ($1, $2, $3, $4)",
        [Decimal.new("100"), Date.utc_today(), "Other user expense", "other_user_id"]
      )

      ctx = base_ctx(fixture, "list")
      assert {:ok, result} = Expenses.execute(ctx)

      # Should only see the seeded expense for fixture.user_id, not the other user's
      descriptions = Enum.map(result.data["expenses"], & &1["description"])
      refute "Other user expense" in descriptions
    end
  end
end
