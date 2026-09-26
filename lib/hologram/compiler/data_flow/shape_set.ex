defmodule Hologram.Compiler.DataFlow.ShapeSet do
  @moduledoc false

  # A set of alternatives of a value (see Hologram.Compiler.DataFlow.shape/0). This module is the
  # one place that knows how such a set is stored, so the analysis never touches the representation:
  # a MapSet for now, sorted lists once every set goes through here.

  alias Hologram.Compiler.DataFlow

  @type t :: MapSet.t(DataFlow.shape())

  @spec all?(t, (DataFlow.shape() -> boolean)) :: boolean
  def all?(set, fun), do: Enum.all?(set, fun)

  @spec any?(t, (DataFlow.shape() -> boolean)) :: boolean
  def any?(set, fun), do: Enum.any?(set, fun)

  @spec empty?(t) :: boolean
  def empty?(set), do: MapSet.size(set) == 0

  @spec filter(t, (DataFlow.shape() -> boolean)) :: t
  def filter(set, fun), do: MapSet.filter(set, fun)

  # The union of the sets the function gives for the elements.
  @spec flat_map(t, (DataFlow.shape() -> t)) :: t
  def flat_map(set, fun) do
    Enum.reduce(set, MapSet.new(), &MapSet.union(&2, fun.(&1)))
  end

  # The set of the shapes the function gives for the elements.
  @spec map(t, (DataFlow.shape() -> DataFlow.shape())) :: t
  def map(set, fun), do: MapSet.new(set, fun)

  @spec member?(t, DataFlow.shape()) :: boolean
  def member?(set, shape), do: MapSet.member?(set, shape)

  @spec new() :: t
  def new, do: MapSet.new()

  @spec new([DataFlow.shape()]) :: t
  def new(shapes), do: MapSet.new(shapes)

  @spec put(t, DataFlow.shape()) :: t
  def put(set, shape), do: MapSet.put(set, shape)

  @spec reduce(t, acc, (DataFlow.shape(), acc -> acc)) :: acc when acc: term
  def reduce(set, acc, fun), do: Enum.reduce(set, acc, fun)

  @spec size(t) :: non_neg_integer
  def size(set), do: MapSet.size(set)

  # The elements in term order, the order they keep once the sets are sorted lists.
  @spec to_list(t) :: [DataFlow.shape()]
  def to_list(set) do
    set
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @spec union(t, t) :: t
  def union(set_1, set_2), do: MapSet.union(set_1, set_2)

  @spec union_all([t]) :: t
  def union_all(sets), do: Enum.reduce(sets, MapSet.new(), &MapSet.union/2)
end
