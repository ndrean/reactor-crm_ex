defmodule CrmReactor.CRM.Expense do
  use Ecto.Schema
  import Ecto.Changeset

  schema "expenses" do
    field :amount, :decimal
    field :currency, :string, default: "EUR"
    field :expense_date, :date
    field :category, :string
    field :description, :string
    field :created_by, :string
    field :contact_id, :integer
    field :status, :string, default: "pending"
    field :attachment_key, :string
    field :archived_at, :utc_datetime

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @categories ~w(restaurant transport hébergement fournitures autre)

  def changeset(expense, attrs) do
    expense
    |> cast(attrs, [
      :amount,
      :currency,
      :expense_date,
      :category,
      :description,
      :created_by,
      :contact_id,
      :status,
      :attachment_key
    ])
    |> validate_required([:amount, :expense_date, :created_by])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:amount, greater_than: 0)
  end
end
