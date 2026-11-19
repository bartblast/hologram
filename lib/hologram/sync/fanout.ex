defmodule Hologram.Sync.Fanout do
  @moduledoc false

  # What each batch the dispatcher reads is handed to for the windows (see
  # `Hologram.Sync.Live.route/2`). Between the log and the evaluators sits the question of which
  # windows a batch of writes could have changed the answer of, and this is where that question is
  # asked and acted on.

  alias Hologram.DB.QueryCache
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
    # Read from the runtime's cache rather than derived per batch: deriving grows with the model,
    # and this runs for every batch before any of it reaches a client. A compile drops the cache, so
    # a live reload is picked up by the next batch. A build where no client checks permissions
    # sends its rows without verdicts, so it has none a change could leave stale.
    edges = Edges.index(QueryCache.permission_checking?())

    transactions
    |> Scoper.affected(Evaluators.live(), edges)
    |> Enum.each(&Evaluator.round(&1, transactions, place))
  end
end
