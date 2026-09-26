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

  alias Hologram.Compiler.DataFlow

  @type t :: [DataFlow.shape()]

  @doc """
  Returns whether the function returns true for every element of the set (true for an empty set).
  """
  @spec all?(t, (DataFlow.shape() -> boolean)) :: boolean
  def all?(set, fun), do: :lists.all(fun, set)

  @doc """
  Returns whether the function returns true for some element of the set (false for an empty set).
  """
  @spec any?(t, (DataFlow.shape() -> boolean)) :: boolean
  def any?(set, fun), do: :lists.any(fun, set)

  @doc """
  Returns whether the set has no elements.
  """
  @spec empty?(t) :: boolean
  def empty?(set), do: set == []

  @doc """
  Returns the set of the elements for which the function returns true.
  """
  @spec filter(t, (DataFlow.shape() -> boolean)) :: t
  def filter(set, fun), do: :lists.filter(fun, set)

  @doc """
  Returns the union of the sets the function returns for the elements.
  """
  @spec flat_map(t, (DataFlow.shape() -> t)) :: t
  def flat_map(set, fun) do
    fun
    |> :lists.map(set)
    |> :ordsets.union()
  end

  @doc """
  Returns the set of the shapes the function returns for the elements.
  """
  @spec map(t, (DataFlow.shape() -> DataFlow.shape())) :: t
  def map(set, fun) do
    fun
    |> :lists.map(set)
    |> :lists.usort()
  end

  @doc """
  Returns whether the shape is an element of the set.
  """
  @spec member?(t, DataFlow.shape()) :: boolean
  def member?(set, shape), do: :ordsets.is_element(shape, set)

  @doc """
  Returns an empty set.
  """
  @spec new() :: t
  def new, do: []

  @doc """
  Returns the set of the given shapes, each once.
  """
  @spec new([DataFlow.shape()]) :: t
  def new(shapes), do: :lists.usort(shapes)

  @doc """
  Returns the set with the shape added.
  """
  @spec put(t, DataFlow.shape()) :: t
  def put(set, shape), do: :ordsets.add_element(shape, set)

  @doc """
  Folds the elements of the set in term order, starting with the given accumulator.
  """
  @spec reduce(t, acc, (DataFlow.shape(), acc -> acc)) :: acc when acc: term
  def reduce(set, acc, fun), do: :lists.foldl(fun, acc, set)

  @doc """
  Returns the number of elements of the set.
  """
  @spec size(t) :: non_neg_integer
  def size(set), do: length(set)

  @doc """
  Returns the elements of the set in term order: the set itself.
  """
  @spec to_list(t) :: [DataFlow.shape()]
  def to_list(set), do: set

  @doc """
  Returns the elements of both sets, once each.
  """
  @spec union(t, t) :: t
  def union(set_1, set_2), do: :ordsets.union(set_1, set_2)

  @doc """
  Returns the elements of every given set, once each.
  """
  @spec union_all([t]) :: t
  def union_all(sets), do: :ordsets.union(sets)
end
