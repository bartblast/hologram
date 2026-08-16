defmodule Hologram.Sync.Pruner do
  @moduledoc false

  # Keeps the effect log from growing without end. All this decides is HOW OFTEN - that only one
  # node of a cluster prunes per round is settled by the delete itself, which takes an advisory
  # lock the others find held.
  #
  # What retention bounds is REPLAY REACH. A client returning to a place the log no longer covers
  # is sent everything it may see instead of the little it missed - slower, never wrong, because
  # whether a place is still covered is read from the log itself.

  use GenServer

  alias Hologram.DB.Outbox

  # How much the log can overrun retention between rounds. At a hundred effects a second an hour
  # leaves some 360k rows above the window, which is nothing against the tens of millions inside
  # it. Policy: it trades that overrun against how often every node wakes to ask for the lock.
  @default_interval_ms :timer.hours(1)

  # How far back a returning client can be caught up from. Policy, and the only thing it decides
  # is when a reconnect costs the whole pot instead of a handful of rows - a week covers a laptop
  # closed over a long weekend.
  @default_retention_seconds 7 * 24 * 60 * 60

  @doc """
  Starts the pruner.

  `:interval_ms` is how often it wakes, and `:retention_seconds` how much of the log it keeps.
  Both default to the configured values.

  Nothing is pruned at start. Every node of a deploy boots at once, and the first thing they would
  all do is ask for the same lock - so the first round is one interval away, by which time they
  have drifted apart. Starting also touches no database, which it must not: this is supervised
  alongside the pool rather than after it.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, default_interval_ms()),
      retention_seconds: Keyword.get(opts, :retention_seconds, default_retention_seconds())
    }

    schedule(state.interval_ms)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:prune, state) do
    schedule(state.interval_ms)

    Outbox.prune(state.retention_seconds)

    {:noreply, state}
  end

  defp default_interval_ms do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:prune_interval_ms, @default_interval_ms)
  end

  defp default_retention_seconds do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:outbox_retention_seconds, @default_retention_seconds)
  end

  defp schedule(interval_ms) do
    Process.send_after(self(), :prune, interval_ms)
  end
end
