defmodule Hologram.Compiler.DataFlow.Store do
  @moduledoc false

  # The per-compile table of interned sets of shapes (see Hologram.Compiler.DataFlow.ShapeSet). A set
  # is stored once, under an id, and a shape holds the ids of the sets nested in it, not the sets: two
  # equal sets get the same id, so a value that holds the same piece a thousand times holds its id a
  # thousand times, and a walk that remembers its result per id goes through the piece once. The
  # analysis described values as trees before, and a value that held its argument many times, put
  # through a fold, grew to gigabytes of copies of the same pieces.
  #
  # The tables are public ETS, so the processes of one compile share them. A store is always passed
  # explicitly: no function looks one up.

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.DataFlow.Store

  defstruct [:counter, :ids, :memo, :sets]

  @type t :: %Store{counter: :atomics.atomics_ref(), ids: PLT.t(), memo: PLT.t(), sets: PLT.t()}

  @doc """
  Returns the content of the set with the given id: a sorted list of shapes whose nested sets are
  ids.
  """
  @spec fetch(t, pos_integer) :: list
  def fetch(%Store{sets: sets}, id), do: :ets.lookup_element(sets.table_ref, id, 2)

  @doc """
  Returns the id of the given content (a sorted list of shapes whose nested sets are ids), the one it
  already has, or a new one. Safe to call from many processes at once: the content is stored under
  its new id before the id is claimed for the content, so no process ever sees an id whose content
  is not there yet, and a process that loses the claim takes the winner's id.
  """
  @spec intern(t, list) :: pos_integer
  def intern(%Store{counter: counter, ids: ids, sets: sets}, content) do
    case :ets.lookup(ids.table_ref, content) do
      [{_content, id}] ->
        id

      [] ->
        id = :atomics.add_get(counter, 1, 1)
        :ets.insert(sets.table_ref, {id, content})

        if :ets.insert_new(ids.table_ref, {content, id}) do
          id
        else
          :ets.delete(sets.table_ref, id)
          :ets.lookup_element(ids.table_ref, content, 2)
        end
    end
  end

  @doc """
  Starts a store: its tables are PLTs started with the given opts (see
  `Hologram.Commons.PLT.start/1`: a `:supervisor` stops them with the supervisor). The empty set is
  interned first, so its id is 1.
  """
  @spec start(T.opts()) :: t
  def start(opts \\ []) do
    store = %Store{
      counter: :atomics.new(1, []),
      ids: PLT.start(opts),
      memo: PLT.start(opts),
      sets: PLT.start(opts)
    }

    intern(store, [])
    store
  end

  @doc """
  Stops the store's tables.
  """
  @spec stop(t) :: :ok
  def stop(%Store{ids: ids, memo: memo, sets: sets}) do
    PLT.stop(ids)
    PLT.stop(memo)
    PLT.stop(sets)
  end
end
