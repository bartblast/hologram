defmodule Hologram.Test.Fixtures.Sync.VanishingEvaluator do
  @moduledoc false

  # Takes a window's registry slot so that starting a real evaluator for it is refused, then stops
  # the moment it is asked to take a subscriber - which is what a session finds when the evaluator
  # it lost the start race to loses its own last subscriber in the instant between.

  use GenServer, restart: :temporary

  alias Hologram.Sync.Evaluator

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    window_id = Keyword.fetch!(opts, :window_id)

    GenServer.start_link(__MODULE__, nil,
      name: {:via, Registry, {Evaluator.registry(), window_id}}
    )
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:subscribe, _subscriber}, _from, state), do: {:stop, :normal, state}
end
