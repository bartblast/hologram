defmodule Hologram.Compiler.DataFlow.ShapeSet do
  @moduledoc false

  # A set of alternatives of a value (see Hologram.Compiler.DataFlow.shape/0). This module is the
  # one place that knows how such a set is stored, so the analysis never touches the representation.
  #
  # A set is a list sorted in term order, without duplicates (an Erlang ordset). A MapSet wraps every
  # set in a struct, which made most of the bytes of a function's summary, and walking one goes
  # through the Enumerable protocol on every call, which is slow where protocols are not consolidated.
  # Every function here is a :lists or :ordsets call instead.
  #
  # A set is always built by this module: a list literal or a list made elsewhere is not sorted, and
  # the sorted-set operations give wrong results on it without failing.
  #
  # Every function takes the store of the compile the set belongs to (see
  # Hologram.Compiler.DataFlow.Store), passed explicitly as the last argument (the set is the
  # subject, so a pipeline of set functions reads as before): sets are about to become ids in it, so that
  # a value holding the same piece many times holds it once.

  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Store

  @type t :: [DataFlow.shape()]

  @doc """
  Returns whether the function returns true for every element of the set (true for an empty set).
  """
  @spec all?(t, (DataFlow.shape() -> boolean), Store.t()) :: boolean
  def all?(set, fun, _store), do: :lists.all(fun, set)

  @doc """
  Returns whether the function returns true for some element of the set (false for an empty set).
  """
  @spec any?(t, (DataFlow.shape() -> boolean), Store.t()) :: boolean
  def any?(set, fun, _store), do: :lists.any(fun, set)

  @doc """
  Returns whether the set has no elements.
  """
  @spec empty?(t, Store.t()) :: boolean
  def empty?(set, _store), do: set == []

  @doc """
  Returns the set of the elements for which the function returns true.
  """
  @spec filter(t, (DataFlow.shape() -> boolean), Store.t()) :: t
  def filter(set, fun, _store), do: :lists.filter(fun, set)

  @doc """
  Returns the union of the sets the function returns for the elements.
  """
  @spec flat_map(t, (DataFlow.shape() -> t), Store.t()) :: t
  def flat_map(set, fun, _store) do
    fun
    |> :lists.map(set)
    |> :ordsets.union()
  end

  @doc """
  Returns the set that the given tree (see `Hologram.Compiler.DataFlow.tree/0`) stands for.
  """
  @spec from_tree(DataFlow.tree(), Store.t()) :: t
  def from_tree(tree, _store), do: tree

  @doc """
  Returns the set of the shapes the function returns for the elements.
  """
  @spec map(t, (DataFlow.shape() -> DataFlow.shape()), Store.t()) :: t
  def map(set, fun, _store) do
    fun
    |> :lists.map(set)
    |> :lists.usort()
  end

  @doc """
  Returns whether the shape is an element of the set.
  """
  @spec member?(t, DataFlow.shape(), Store.t()) :: boolean
  def member?(set, shape, _store), do: :ordsets.is_element(shape, set)

  @doc """
  Returns an empty set.
  """
  @spec new(Store.t()) :: t
  def new(_store), do: []

  @doc """
  Returns the set of the given shapes, each once.
  """
  @spec new([DataFlow.shape()], Store.t()) :: t
  def new(shapes, _store), do: :lists.usort(shapes)

  @doc """
  Returns the set with the shape added.
  """
  @spec put(t, DataFlow.shape(), Store.t()) :: t
  def put(set, shape, _store), do: :ordsets.add_element(shape, set)

  @doc """
  Folds the elements of the set in term order, starting with the given accumulator.
  """
  @spec reduce(t, acc, (DataFlow.shape(), acc -> acc), Store.t()) :: acc when acc: term
  def reduce(set, acc, fun, _store), do: :lists.foldl(fun, acc, set)

  @doc """
  Returns the number of elements of the set.
  """
  @spec size(t, Store.t()) :: non_neg_integer
  def size(set, _store), do: length(set)

  @doc """
  Returns the elements of the set in term order.
  """
  @spec to_list(t, Store.t()) :: [DataFlow.shape()]
  def to_list(set, _store), do: set

  @doc """
  Returns the elements of both sets, once each.
  """
  @spec union(t, t, Store.t()) :: t
  def union(set_1, set_2, _store), do: :ordsets.union(set_1, set_2)

  @doc """
  Returns the elements of every given set, once each.
  """
  @spec union_all([t], Store.t()) :: t
  def union_all(sets, _store), do: :ordsets.union(sets)
end
