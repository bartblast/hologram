defmodule Hologram.Sync.WindowStore do
  @moduledoc false

  # What this node is currently keeping up to date, and for how many sessions. Sessions register
  # what they need as they connect and give it back as they go, and the same window asked for by
  # a hundred of them is held once - which is what lets the work behind it be done once too.
  #
  # The process exists to own the table and to outlive the sessions writing into it. Registering
  # goes straight to ETS rather than through the process: it happens once per window per session
  # and would otherwise queue every connecting client behind one mailbox.

  use GenServer

  @table_name :hologram_sync_windows

  @doc """
  Returns the name of the ETS table backing the store.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns every registered window as a `{key, term}` pair, where a key is the `{window id,
  params}` the window is kept for.
  """
  @spec all() :: list({{String.t(), map}, map})
  def all do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {key, term, _subscribers} -> {key, term} end)
  end

  @doc """
  Returns the term registered for the given key, or nil when nothing holds it.
  """
  @spec fetch({String.t(), map}) :: map | nil
  def fetch(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, term, _subscribers}] -> term
      [] -> nil
    end
  end

  @doc """
  Registers a session's interest in the window the given term describes, under the given key, and
  returns how many sessions now hold it.

  Registering the same key again counts one more holder rather than replacing what is there: the
  term is a property of the key, so two holders of one key are asking for the same thing.
  """
  @spec register({String.t(), map}, map) :: pos_integer
  def register(key, term) do
    # Only the first holder writes the term, and only if it is not already there - so two
    # sessions registering at once cannot both count themselves as the first.
    if :ets.insert_new(@table_name, {key, term, 1}) do
      1
    else
      :ets.update_counter(@table_name, key, {3, 1})
    end
  end

  @doc """
  Gives back a session's interest in the given key, and returns how many sessions still hold it.

  The window is forgotten once the last one lets go. Giving back what was never held, or has
  already been forgotten, answers zero rather than raising - a session cleaning up after a crash
  cannot know which of its registrations survived.
  """
  @spec unregister({String.t(), map}) :: non_neg_integer
  def unregister(key) do
    case :ets.lookup(@table_name, key) do
      [] ->
        0

      [{^key, _term, _subscribers}] ->
        drop_holder(key)
    end
  end

  @doc """
  Starts the store.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

  defp drop_holder(key) do
    case :ets.update_counter(@table_name, key, {3, -1}) do
      0 ->
        :ets.delete(@table_name, key)

        0

      remaining ->
        remaining
    end
  end
end
