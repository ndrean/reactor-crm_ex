defmodule CrmReactor.QueryHelpers do
  @moduledoc "Shared helpers for safe Ecto query construction."

  @doc """
  Wraps a value in `%...%` for use with `ilike`, escaping `\\`, `%`, and `_`
  so that LLM-provided strings cannot widen the search pattern.
  """
  @spec ilike_pattern(String.t()) :: String.t()
  def ilike_pattern(value) when is_binary(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
  end
end
