defmodule CrmReactor.AI.ConversationCache do
  @moduledoc """
  ETS-backed conversation context cache for pronoun/reference resolution.

  Stores the last 3 user/assistant exchange pairs per user_id with a 5-minute TTL.
  Uses a public ETS table — any process can read/write directly (no GenServer).
  """

  @table :conversation_cache
  @ttl_ms 300_000
  @max_pairs 3

  @doc "Creates the ETS table. Call once during application startup."
  def create_table do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      write_concurrency: true,
      read_concurrency: true
    ])
  end

  @doc """
  Returns recent conversation pairs for a user, pruned by TTL.
  Returns `[{:user, text}, {:assistant, text}, ...]` (most recent last).
  """
  def get(user_id) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, entries}] ->
        now = System.monotonic_time(:millisecond)

        entries
        |> Enum.filter(fn {_role, _text, ts} -> now - ts < @ttl_ms end)
        |> Enum.take(-@max_pairs * 2)
        |> Enum.map(fn {role, text, _ts} -> {role, text} end)

      [] ->
        []
    end
  end

  @doc "Appends a user/assistant exchange pair, pruning old entries."
  def put(user_id, user_text, assistant_text) do
    now = System.monotonic_time(:millisecond)

    existing =
      case :ets.lookup(@table, user_id) do
        [{^user_id, entries}] ->
          entries
          |> Enum.filter(fn {_role, _text, ts} -> now - ts < @ttl_ms end)

        [] ->
          []
      end

    updated =
      (existing ++ [{:user, user_text, now}, {:assistant, assistant_text, now}])
      |> Enum.take(-@max_pairs * 2)

    :ets.insert(@table, {user_id, updated})
    :ok
  end
end
