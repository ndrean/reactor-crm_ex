ExUnit.start(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(CrmReactor.Repo, :manual)

mistral_ok? =
  case System.get_env("MISTRAL_API_KEY") do
    nil ->
      false

    key ->
      case Req.post("https://api.mistral.ai/v1/chat/completions",
             auth: {:bearer, key},
             json: %{
               model: "mistral-small-latest",
               messages: [%{role: "user", content: "hi"}],
               max_tokens: 1
             },
             retry: false,
             receive_timeout: 5_000
           ) do
        {:ok, %{status: 200}} -> true
        _ -> false
      end
  end

Application.put_env(:crm_reactor, :mistral_available, mistral_ok?)

unless mistral_ok? do
  ExUnit.configure(exclude: [:requires_mistral | ExUnit.configuration()[:exclude]])
end
