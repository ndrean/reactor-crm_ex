defmodule CrmReactor.Workers.WebhookWorker do
  @moduledoc "Delivers workflow results to tenant webhook URLs with HMAC signing."
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  @impl true
  def perform(%Oban.Job{
        args: %{"webhook_url" => url, "webhook_secret" => secret, "payload" => payload}
      }) do
    body = Jason.encode!(payload)

    signature =
      :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

    case Req.post(url,
           body: body,
           headers: [
             {"content-type", "application/json"},
             {"x-crm-signature", "sha256=#{signature}"}
           ],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, %{status: s}} -> {:error, "HTTP #{s}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
