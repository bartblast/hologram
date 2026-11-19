defmodule Hologram.Sync.Gate do
  @moduledoc false

  # How many returning clients a node catches up at once. A deploy or a node restart closes every
  # stream together, and nearly every browser comes back within seconds - each one reading the ids
  # its user may read and what it missed. Let in all at once, they would take the database from the
  # app's own requests, which matter more than how soon sync catches up: the app keeps working from
  # what each browser holds meanwhile. So the catch-ups take turns, in the order they asked, a few at
  # a time.
  #
  # A session asks to be let in and is told `{:gate, :open}` when its turn comes; it leaves once its
  # client is caught up. One that ends before either - its client went, or it was cut - gives its
  # turn up by ending: the gate watches every session it knows of.

  use GenServer

  @default_catchups_at_once 4

  @doc """
  Starts the gate, letting in as many catch-ups at once as `catchups_at_once/0` answers when it
  starts.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Asks the given gate to let the calling process in, and watches the gate: the caller is sent
  `{:gate, :open}` once its turn comes, and a `:DOWN` with the returned reference if the gate goes
  first. A process asks once, and leaves with `leave/1`.
  """
  @spec ask(atom | pid) :: reference
  def ask(gate \\ __MODULE__) do
    ref = Process.monitor(gate)

    GenServer.cast(gate, {:ask, self()})

    ref
  end

  @doc """
  Returns how many catch-ups a node runs at once: the `:catchups_at_once` key of the `:sync`
  config, 4 by default. Anything but a positive integer raises: a gate letting nobody in would
  leave every returning client waiting forever, with nothing to say so.

  A fixed number rather than one worked out from the node, so the database connections they take
  can be counted per node.
  """
  @spec catchups_at_once() :: pos_integer
  def catchups_at_once do
    configured =
      :hologram
      |> Application.get_env(:sync, [])
      |> Keyword.get(:catchups_at_once)

    case configured do
      nil ->
        @default_catchups_at_once

      count when is_integer(count) and count > 0 ->
        count

      other ->
        raise ArgumentError,
              "config :hologram, :sync, catchups_at_once: expects a positive integer, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc """
  Tells the given gate the calling process is done, which lets the next one in.
  """
  @spec leave(atom | pid) :: :ok
  def leave(gate \\ __MODULE__) do
    GenServer.cast(gate, {:leave, self()})
  end

  # The ones waiting are kept twice: in the order they asked, and by the reference watching each.
  # One that ends while it waits is taken out of the second alone, and passed over when its turn
  # comes - taking it out of the queue would cost a pass over everyone waiting, and a deploy can
  # leave tens of thousands waiting while tabs close among them.
  @impl GenServer
  def init(nil) do
    {:ok, %{holders: %{}, limit: catchups_at_once(), queue: :queue.new(), waiting: MapSet.new()}}
  end

  @impl GenServer
  def handle_cast({:ask, pid}, state) do
    ref = Process.monitor(pid)

    queued = %{
      state
      | queue: :queue.in({pid, ref}, state.queue),
        waiting: MapSet.put(state.waiting, ref)
    }

    {:noreply, admit(queued)}
  end

  def handle_cast({:leave, pid}, state) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        {:noreply, state}

      {ref, holders} ->
        Process.demonitor(ref, [:flush])

        {:noreply, admit(%{state | holders: holders})}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.holders, pid) do
      {^ref, holders} ->
        {:noreply, admit(%{state | holders: holders})}

      _not_held ->
        {:noreply, %{state | waiting: MapSet.delete(state.waiting, ref)}}
    end
  end

  # Lets the longest waiting in while there is room, passing over the ones that ended meanwhile.
  defp admit(state) do
    with true <- map_size(state.holders) < state.limit,
         {{:value, {pid, ref}}, queue} <- :queue.out(state.queue) do
      if MapSet.member?(state.waiting, ref) do
        send(pid, {:gate, :open})

        admit(%{
          state
          | holders: Map.put(state.holders, pid, ref),
            queue: queue,
            waiting: MapSet.delete(state.waiting, ref)
        })
      else
        admit(%{state | queue: queue})
      end
    else
      _full_or_empty -> state
    end
  end
end
