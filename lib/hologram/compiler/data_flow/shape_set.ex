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

  @spec all?(t, (DataFlow.shape() -> boolean)) :: boolean
  def all?(set, fun), do: :lists.all(fun, set)

  @spec any?(t, (DataFlow.shape() -> boolean)) :: boolean
  def any?(set, fun), do: :lists.any(fun, set)

  @spec empty?(t) :: boolean
  def empty?(set), do: set == []

  @spec filter(t, (DataFlow.shape() -> boolean)) :: t
  def filter(set, fun), do: :lists.filter(fun, set)

  # The union of the sets the function gives for the elements.
  @spec flat_map(t, (DataFlow.shape() -> t)) :: t
  def flat_map(set, fun) do
    fun
    |> :lists.map(set)
    |> :ordsets.union()
  end

  # The set of the shapes the function gives for the elements.
  @spec map(t, (DataFlow.shape() -> DataFlow.shape())) :: t
  def map(set, fun) do
    fun
    |> :lists.map(set)
    |> :lists.usort()
  end

  @spec member?(t, DataFlow.shape()) :: boolean
  def member?(set, shape), do: :ordsets.is_element(shape, set)

  @spec new() :: t
  def new, do: []

  @spec new([DataFlow.shape()]) :: t
  def new(shapes), do: :lists.usort(shapes)

  @spec put(t, DataFlow.shape()) :: t
  def put(set, shape), do: :ordsets.add_element(shape, set)

  @spec reduce(t, acc, (DataFlow.shape(), acc -> acc)) :: acc when acc: term
  def reduce(set, acc, fun), do: :lists.foldl(fun, acc, set)

  @spec size(t) :: non_neg_integer
  def size(set), do: length(set)

  # The elements in term order: the set itself.
  @spec to_list(t) :: [DataFlow.shape()]
  def to_list(set), do: set

  @spec union(t, t) :: t
  def union(set_1, set_2), do: :ordsets.union(set_1, set_2)

  @spec union_all([t]) :: t
  def union_all(sets), do: :ordsets.union(sets)
end
