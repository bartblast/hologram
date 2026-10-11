defmodule Hologram.Sync.Fanout do
  @moduledoc false

  # What the dispatcher hands each window it read something for. Between the log and the
  # evaluators sits the question of which windows a batch of writes could have changed the answer
  # of, and this is where that question is asked and acted on.

  alias Hologram.Entity.Model
  alias Hologram.Policy.Edges
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Scoper

  @doc """
  Hands the given transactions, and the place they were read from, to the evaluator of every
  window they could have changed.

  Only windows this node is keeping up to date are considered, and a window nobody holds has no
  evaluator to tell - a node does the work its own clients are waiting on and no more.

  Every affected window is handed the whole batch rather than the part that concerns it. What a
  window makes of an effect naming a row it does not hold is nothing, and deciding that here
  would be deciding it twice.
  """
  @spec route(list({non_neg_integer, list(map)}), {non_neg_integer, non_neg_integer}) :: :ok
  def route(transactions, place) do
    # Derived per batch rather than kept, from the cached model: deriving costs nothing once the
    # policies are built, and the list it is derived from is the one fact a sweep produces - cached
    # for the runtime and dropped by a compile, so a live reload is picked up by the next batch.
    edges = Edges.derive(Model.entity_types())

    transactions
    |> Scoper.affected(Evaluators.live(), edges)
    |> Enum.each(&Evaluator.round(&1, transactions, place))
  end
end
