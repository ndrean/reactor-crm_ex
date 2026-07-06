defmodule CrmReactor.Storage do
  @moduledoc """
  Behaviour for file storage backends.

  Implementations: `CrmReactor.Storage.Local` (filesystem), future B2/S3.
  Configured via `config :crm_reactor, :file_storage, Module`.
  """

  @max_size_bytes 5 * 1024 * 1024

  @callback put(tenant_schema :: String.t(), filename :: String.t(), content :: binary()) ::
              {:ok, storage_key :: String.t()} | {:error, term()}

  @callback get(storage_key :: String.t()) :: {:ok, binary()} | {:error, term()}

  @callback delete(storage_key :: String.t()) :: :ok | {:error, term()}

  def put(_tenant_schema, _filename, content) when byte_size(content) > @max_size_bytes do
    {:error, :file_too_large}
  end

  def put(tenant_schema, filename, content) do
    impl().put(tenant_schema, filename, content)
  end

  def get(storage_key), do: impl().get(storage_key)

  def delete(storage_key), do: impl().delete(storage_key)

  def max_size_bytes, do: @max_size_bytes

  defp impl do
    Application.get_env(:crm_reactor, :file_storage, CrmReactor.Storage.Local)
  end
end
