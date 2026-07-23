defmodule CrmReactor.Storage.S3 do
  @moduledoc """
  S3-compatible storage backend (MinIO, B2, R2).
  Key format: `{namespace}/{hex_id}-{sanitized_filename}`.
  """

  @behaviour CrmReactor.Storage

  @impl true
  def put(namespace, filename, content) do
    key = "#{namespace}/#{unique_id()}-#{sanitize(filename)}"

    case ExAws.S3.put_object(bucket(), key, content)
         |> ExAws.request(ex_aws_config()) do
      {:ok, _} -> {:ok, key}
      {:error, _} = err -> err
    end
  end

  @impl true
  def get(key) do
    case ExAws.S3.get_object(bucket(), key)
         |> ExAws.request(ex_aws_config()) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, _} = err -> err
    end
  end

  @impl true
  def delete(key) do
    case ExAws.S3.delete_object(bucket(), key)
         |> ExAws.request(ex_aws_config()) do
      {:ok, _} -> :ok
      {:error, {:http_error, 404, _}} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Generate a presigned GET URL valid for `expires_in` seconds (default 300)."
  def presigned_url(key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 10)
    public_config = ex_aws_config() |> Keyword.merge(public_s3_config())
    config = ExAws.Config.new(:s3, public_config)
    ExAws.S3.presigned_url(config, :get, bucket(), key, expires_in: expires_in)
  end

  defp bucket do
    Application.get_env(:crm_reactor, :s3_bucket, "crm-reactor")
  end

  defp ex_aws_config do
    Application.get_env(:crm_reactor, :ex_aws_config, [])
  end

  defp public_s3_config do
    Application.get_env(:crm_reactor, :s3_public_url, [])
  end

  defp unique_id, do: Ecto.UUID.generate()

  defp sanitize(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 60)
  end
end
