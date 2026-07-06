defmodule CrmReactor.Storage.Local do
  @moduledoc """
  Filesystem storage backend. Stores files under `config :crm_reactor, :storage_path`.
  Key format: `{tenant_schema}/{hex_id}-{sanitized_filename}`.
  """

  @behaviour CrmReactor.Storage

  @impl true
  def put(tenant_schema, filename, content) do
    key = "#{tenant_schema}/#{unique_id()}-#{sanitize(filename)}"
    path = full_path(key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, content) do
      {:ok, key}
    end
  end

  @impl true
  def get(key) do
    File.read(full_path(key))
  end

  @impl true
  def delete(key) do
    case File.rm(full_path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _} = err -> err
    end
  end

  defp full_path(key) do
    base = Application.get_env(:crm_reactor, :storage_path, "priv/uploads")
    Path.join(base, key)
  end

  defp unique_id, do: Ecto.UUID.generate()

  defp sanitize(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 60)
  end
end
