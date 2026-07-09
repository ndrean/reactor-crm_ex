defmodule CrmReactor.Workers.RoutingSignalWorker do
  @moduledoc "Oban worker: persists a routing signal row from a two-pass classification."
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias CrmReactor.AI.RoutingSignal
  alias CrmReactor.Repo

  @impl true
  def perform(%Oban.Job{args: args}) do
    %RoutingSignal{}
    |> RoutingSignal.changeset(args)
    |> Repo.insert()

    :ok
  end
end
