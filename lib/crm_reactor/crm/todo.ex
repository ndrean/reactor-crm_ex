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
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :location, :string
    field :reminder_minutes, :integer, default: 30
    field :reminder_job_id, :integer
    field :contact_name, :string, virtual: true

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [
      :subject,
      :due_date,
      :created_by,
      :done,
      :start_date,
      :contact_id,
      :starts_at,
      :ends_at,
      :location,
      :reminder_minutes,
      :reminder_job_id
    ])
    |> validate_required([:subject, :created_by])
  end
end
