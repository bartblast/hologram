defmodule Hologram.Compiler.DataFlow.ShapeSet do
  @moduledoc false

  # A set of alternatives of a value (see Hologram.Compiler.DataFlow.shape/0). This module is the
  # one place that knows how such a set is stored, so the analysis never touches the representation.
  #
  # A set is an id in the store of its compile (see Hologram.Compiler.DataFlow.Store), which holds its
  # content once: the shapes, sorted in term order, without duplicates (an Erlang ordset), each shape
  # holding the ids of the sets nested in it. Two equal sets are one id, so a value that holds the same
  # piece many times holds its id, not copies: the analysis described values as trees before, and a
  # value that held its argument many times, put through a fold, grew to gigabytes of copies.
  #
  # Every function takes the store as its last argument, passed explicitly (the set is the subject,
  # so a pipeline of set functions reads as a pipeline). A set is always built by this module: every
  # result is interned, so equal content always gives the same id.

  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Store

  # The id of the empty set: the store interns it first (see Store.start/1).
  @empty 1

  @type t :: pos_integer

  @doc """
  Returns whether the function returns true for every element of the set (true for an empty set).
  """
  @spec all?(t, (DataFlow.shape() -> boolean), Store.t()) :: boolean
  def all?(set, fun, store), do: :lists.all(fun, Store.fetch(store, set))

  @doc """
  Returns whether the function returns true for some element of the set (false for an empty set).
  """
  @spec any?(t, (DataFlow.shape() -> boolean), Store.t()) :: boolean
  def any?(set, fun, store), do: :lists.any(fun, Store.fetch(store, set))

  @doc """
  Returns whether the set has no elements.
  """
  @spec empty?(t, Store.t()) :: boolean
  def empty?(set, _store), do: set == @empty

  @doc """
  Returns the set of the elements for which the function returns true.
  """
  @spec filter(t, (DataFlow.shape() -> boolean), Store.t()) :: t
  def filter(set, fun, store) do
    Store.intern(store, :lists.filter(fun, Store.fetch(store, set)))
  end

  @doc """
  Returns the union of the sets the function returns for the elements.
  """
  @spec flat_map(t, (DataFlow.shape() -> t), Store.t()) :: t
  def flat_map(set, fun, store) do
    fun
    |> :lists.map(Store.fetch(store, set))
    |> union_all(store)
  end

  @doc """
  Returns the set that the given tree (see `Hologram.Compiler.DataFlow.tree/0`) stands for, its nested
  trees interned first.
  """
  @spec from_tree(DataFlow.tree(), Store.t()) :: t
  def from_tree(tree, store) do
    tree
    |> Enum.map(&DataFlow.map_nested(&1, fn nested -> from_tree(nested, store) end))
    |> new(store)
  end

  @doc """
  Returns the set of the shapes the function returns for the elements.
  """
  @spec map(t, (DataFlow.shape() -> DataFlow.shape()), Store.t()) :: t
  def map(set, fun, store) do
    fun
    |> :lists.map(Store.fetch(store, set))
    |> new(store)
  end

  @doc """
  Returns whether the shape is an element of the set.
  """
  @spec member?(t, DataFlow.shape(), Store.t()) :: boolean
  def member?(set, shape, store), do: :ordsets.is_element(shape, Store.fetch(store, set))

  @doc """
  Returns an empty set.
  """
  @spec new(Store.t()) :: t
  def new(_store), do: @empty

  @doc """
  Returns the set of the given shapes, each once.
  """
  @spec new([DataFlow.shape()], Store.t()) :: t
  def new(shapes, store), do: Store.intern(store, :lists.usort(shapes))

  @doc """
  Returns the set with the shape added.
  """
  @spec put(t, DataFlow.shape(), Store.t()) :: t
  def put(set, shape, store) do
    Store.intern(store, :ordsets.add_element(shape, Store.fetch(store, set)))
  end

  @doc """
  Folds the elements of the set in term order, starting with the given accumulator.
  """
  @spec reduce(t, acc, (DataFlow.shape(), acc -> acc), Store.t()) :: acc when acc: term
  def reduce(set, acc, fun, store), do: :lists.foldl(fun, acc, Store.fetch(store, set))

  @doc """
  Returns the number of elements of the set.
  """
  @spec size(t, Store.t()) :: non_neg_integer
  def size(set, store), do: length(Store.fetch(store, set))

  @doc """
  Returns the elements of the set in term order, their nested sets ids.
  """
  @spec to_list(t, Store.t()) :: [DataFlow.shape()]
  def to_list(set, store), do: Store.fetch(store, set)

  @doc """
  Returns the elements of both sets, once each.
  """
  @spec union(t, t, Store.t()) :: t
  def union(set, set, _store), do: set

  def union(set_1, set_2, store) do
    Store.intern(store, :ordsets.union(Store.fetch(store, set_1), Store.fetch(store, set_2)))
  end

  @doc """
  Returns the elements of every given set, once each.
  """
  @spec union_all([t], Store.t()) :: t
  def union_all(sets, store) do
    case :lists.usort(sets) do
      [] -> @empty
      [set] -> set
      distinct -> Store.intern(store, :ordsets.union(Enum.map(distinct, &Store.fetch(store, &1))))
    end
  end
end
