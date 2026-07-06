defmodule CrmReactor.CRM.Todo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todos" do
    field :subject, :string
    field :due_date, :date
    field :created_by, :string
    field :done, :boolean, default: false
    field :start_date, :date
    field :contact_id, :integer

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:subject, :due_date, :created_by, :done, :start_date, :contact_id])
    |> validate_required([:subject, :created_by])
  end
end
