defmodule Hologram.Sync.ResultStore do
  @moduledoc false

  # What each window last held, kept once per node rather than once per session. A round writes a
  # new version of a window's rows here and every session reading that window reads this copy -
  # which is the whole reason a hundred sessions asking for one window cost one query and one set
  # of rows rather than a hundred of each.
  #
  # A few versions are kept, not one: a session that was slow to be written to was last told about
  # an older round, and telling it what changed since means having what it was told. How far back
  # that reaches is the ring length - past it, a session is sent everything again.

  use GenServer

  @default_ring_length 3

  @table_name :hologram_sync_results

  @doc """
  Returns the name of the ETS table backing the store.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns the rows and ids a window held at the given version, or nil once that version has been
  pruned or was never written.
  """
  @spec fetch(String.t(), pos_integer) :: %{ids: MapSet.t(), rows: map} | nil
  def fetch(key, version) do
    case :ets.lookup(@table_name, {key, version}) do
      [{_key_version, result}] -> result
      [] -> nil
    end
  end

  @doc """
  Forgets every version of the given window, for when nothing holds it any more.
  """
  @spec forget(String.t()) :: :ok
  def forget(key) do
    key
    |> versions()
    |> Enum.each(&:ets.delete(@table_name, {key, &1}))
  end

  @doc """
  Writes a round's rows as the given window's newest version, keyed by row id, and drops the
  versions that have fallen out of the ring.

  Ids are kept beside the rows because membership is what a round is diffed by, and rebuilding
  the set per session would undo the sharing this store exists for.
  """
  @spec put(String.t(), pos_integer, list(struct)) :: :ok
  def put(key, version, rows) do
    by_id = Map.new(rows, &{&1.id, &1})

    ids =
      by_id
      |> Map.keys()
      |> MapSet.new()

    result = %{ids: ids, rows: by_id}

    :ets.insert(@table_name, {{key, version}, result})

    prune(key, version)
  end

  @doc """
  Returns how many versions of a window are kept.
  """
  @spec ring_length() :: pos_integer
  def ring_length do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:result_ring_length, @default_ring_length)
  end

  @doc """
  Starts the store.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the versions of the given window that are still kept, newest first.
  """
  @spec versions(String.t()) :: list(pos_integer)
  def versions(key) do
    @table_name
    |> :ets.match({{key, :"$1"}, :_})
    |> Enum.map(fn [version] -> version end)
    |> Enum.sort(:desc)
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  # A window's versions are written one after another, and every write drops the one that fell out
  # of the ring as it lands - so the versions held are always the last few, and which one is
  # leaving is a subtraction rather than a question for the table. Asking the table means matching
  # an unbound version inside the key, and a hash table can answer that only by walking every
  # version of every window: work that grows with how much the node holds, done once per round of
  # every window that had one.
  #
  # Nothing to drop until the ring has filled, which is what the guard says.
  defp prune(key, version) do
    dropped = version - ring_length()

    if dropped > 0, do: :ets.delete(@table_name, {key, dropped})

    :ok
  end
end
