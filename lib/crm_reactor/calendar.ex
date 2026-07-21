defmodule CrmReactor.Calendar do
  @moduledoc false

  import Ecto.Query

  alias CrmReactor.CRM.Todo
  alias CrmReactor.Repo

  @lookback_days 30

  def build_feed(account, tenant_schema) do
    tenant_id = String.replace_prefix(tenant_schema, "customer_", "")

    events =
      account.email
      |> feedable_todos(tenant_schema)
      |> Enum.map(&todo_to_event(&1, tenant_id))

    %ICal{events: events, method: "PUBLISH"}
    |> ICal.to_ics()
    |> IO.iodata_to_binary()
    |> String.replace("\r\n", "\n")
    |> String.replace("\n", "\r\n")
  end

  defp feedable_todos(email, tenant_schema) do
    cutoff = Date.utc_today() |> Date.add(-@lookback_days)
    cutoff_dt = DateTime.new!(cutoff, ~T[00:00:00], "Etc/UTC")

    Todo
    |> where([t], t.created_by == ^email and t.done == false and is_nil(t.archived_at))
    |> has_date()
    |> within_lookback(cutoff, cutoff_dt)
    |> order_by([t], asc: t.starts_at, asc: t.due_date)
    |> Repo.all(prefix: tenant_schema)
  end

  defp has_date(query) do
    where(
      query,
      [t],
      not is_nil(t.due_date) or not is_nil(t.starts_at) or not is_nil(t.start_date)
    )
  end

  defp within_lookback(query, cutoff, cutoff_dt) do
    where(
      query,
      [t],
      (not is_nil(t.starts_at) and t.starts_at >= ^cutoff_dt) or
        (is_nil(t.starts_at) and not is_nil(t.due_date) and t.due_date >= ^cutoff) or
        (is_nil(t.starts_at) and is_nil(t.due_date) and not is_nil(t.start_date) and
           t.start_date >= ^cutoff)
    )
  end

  defp todo_to_event(todo, tenant_id) do
    %ICal.Event{
      uid: "todo-#{todo.id}@#{tenant_id}.crm",
      summary: todo.subject,
      location: todo.location
    }
    |> set_times(todo)
  end

  defp set_times(event, %{starts_at: %DateTime{} = start} = todo) do
    ends_at = todo.ends_at || DateTime.add(start, 3600, :second)
    %{event | dtstart: start, dtend: ends_at}
  end

  defp set_times(event, %{due_date: %Date{} = date}) do
    %{event | dtstart: date, dtend: Date.add(date, 1)}
  end

  defp set_times(event, %{start_date: %Date{} = date}) do
    %{event | dtstart: date, dtend: Date.add(date, 1)}
  end

  defp set_times(event, _), do: event
end
