defmodule CrmReactor.Workers.ExampleReviewWorker do
  @moduledoc """
  Daily Oban cron job that uses mistral-large-latest to review routing mismatches
  from the last 24 hours and auto-grow the example bank.

  Queries routing_signals where pass1_workflow != pass2_workflow (or llm_confirmed = false)
  and reviewed = false, sends them to the review model for validation, and inserts
  confirmed corrections as new registry_examples with embeddings.

  Caps at 20 new examples per run to avoid flooding the example bank.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  import Ecto.Query

  alias CrmReactor.AI.{ExamplesCache, RoutingSignal}
  alias CrmReactor.Repo
  alias CrmReactor.Tenants.RegistryExample

  require Logger

  @max_new_examples 20

  @impl true
  def perform(%Oban.Job{}) do
    signals = fetch_unreviewed_mismatches()

    if signals == [] do
      Logger.info("ExampleReviewWorker: no unreviewed mismatches found")
      :ok
    else
      Logger.info("ExampleReviewWorker: reviewing #{length(signals)} mismatches")
      review_and_learn(signals)
    end
  end

  defp fetch_unreviewed_mismatches do
    cutoff = DateTime.utc_now() |> DateTime.add(-24 * 3600, :second)

    from(s in RoutingSignal,
      where: s.reviewed == false,
      where: s.inserted_at >= ^cutoff,
      where: s.llm_confirmed == false,
      where: not is_nil(s.pass1_workflow) and not is_nil(s.pass2_workflow),
      where: s.pass1_workflow != s.pass2_workflow,
      order_by: [asc: s.inserted_at],
      limit: 50
    )
    |> Repo.all()
  end

  defp review_and_learn(signals) do
    verdicts = judge_mismatches(signals)
    added = insert_confirmed_examples(signals, verdicts)
    mark_reviewed(signals)

    if added > 0 do
      ExamplesCache.reload()
      Logger.info("ExampleReviewWorker: added #{added} new examples, cache reloaded")
    end

    :ok
  end

  defp judge_mismatches(signals) do
    model = Application.get_env(:crm_reactor, :mistral_review_model, "mistral-large-latest")
    api_key = Application.fetch_env!(:crm_reactor, :mistral_api_key)

    prompt = build_review_prompt(signals)

    base_url = Application.get_env(:crm_reactor, :mistral_api_url, "https://api.mistral.ai")

    case Req.post("#{base_url}/v1/chat/completions",
           json: %{
             model: model,
             messages: [
               %{role: "system", content: system_prompt()},
               %{role: "user", content: prompt}
             ],
             response_format: %{type: "json_object"},
             temperature: 0
           },
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_verdicts(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("ExampleReviewWorker: Mistral error #{status}: #{inspect(body)}")
        %{}

      {:error, reason} ->
        Logger.warning("ExampleReviewWorker: request failed: #{inspect(reason)}")
        %{}
    end
  end

  defp system_prompt do
    """
    You are an intent-routing quality reviewer for a French-language CRM assistant.

    The system routes user messages to workflows (contacts, todos, data, help).
    Pass 1 (fast, cheap model) sometimes misroutes. Pass 2 (stronger model) corrects it.

    For each mismatch, decide which workflow is correct for the user's input.
    Return JSON: {"verdicts": [{"id": <signal_id>, "correct_workflow": "<workflow_name>", "is_good_example": true/false}]}

    Set is_good_example=true only if the input is a clear, unambiguous example of that workflow
    that would help train routing. Reject vague, multi-intent, or context-dependent inputs.
    """
  end

  defp build_review_prompt(signals) do
    items =
      Enum.map_join(signals, "\n", fn s ->
        "ID=#{s.id} | Input: \"#{s.raw_input}\" | Pass1: #{s.pass1_workflow} (#{s.pass1_confidence}) | Pass2: #{s.pass2_workflow}"
      end)

    "Review these routing mismatches:\n#{items}"
  end

  defp parse_verdicts(body) do
    [choice | _] = body["choices"]

    case Jason.decode(choice["message"]["content"]) do
      {:ok, %{"verdicts" => verdicts}} when is_list(verdicts) ->
        Map.new(verdicts, fn v ->
          {v["id"], %{workflow: v["correct_workflow"], good: v["is_good_example"] == true}}
        end)

      {:ok, other} ->
        Logger.warning("ExampleReviewWorker: unexpected response shape: #{inspect(other)}")
        %{}

      {:error, reason} ->
        Logger.warning("ExampleReviewWorker: JSON decode error: #{inspect(reason)}")
        %{}
    end
  end

  defp insert_confirmed_examples(signals, verdicts) do
    embedder = Application.get_env(:crm_reactor, :embedder, CrmReactor.AI.Embedder)

    signals
    |> Enum.filter(fn s ->
      case Map.get(verdicts, s.id) do
        %{good: true} -> true
        _ -> false
      end
    end)
    |> Enum.take(@max_new_examples)
    |> Enum.reduce(0, fn signal, count ->
      %{workflow: workflow} = Map.fetch!(verdicts, signal.id)

      embedding =
        case embedder.embed(signal.raw_input) do
          {:ok, vec} -> vec
          {:error, _} -> nil
        end

      case %RegistryExample{}
           |> RegistryExample.changeset(%{
             workflow_name: workflow,
             phrase: signal.raw_input,
             embedding: embedding
           })
           |> Repo.insert() do
        {:ok, _} ->
          count + 1

        {:error, reason} ->
          Logger.warning("ExampleReviewWorker: failed to insert example: #{inspect(reason)}")
          count
      end
    end)
  end

  defp mark_reviewed(signals) do
    ids = Enum.map(signals, & &1.id)

    from(s in RoutingSignal, where: s.id in ^ids)
    |> Repo.update_all(set: [reviewed: true])
  end
end
