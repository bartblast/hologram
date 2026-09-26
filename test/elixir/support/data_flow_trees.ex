defmodule Hologram.Test.DataFlowTrees do
  @moduledoc false

  # Sets of shapes written out as trees, for tests: a tree is a set as a sorted list without
  # duplicates, its nested sets trees too (see Hologram.Compiler.DataFlow.to_tree/2). Tests write
  # expected values as trees and compare them with the analysis's answers written out as trees.

  @doc """
  Returns the empty tree set.
  """
  @spec tree_set() :: list
  def tree_set, do: []

  @doc """
  Returns the tree set of the given shapes: sorted, each once.
  """
  @spec tree_set(list) :: list
  def tree_set(shapes), do: :lists.usort(shapes)
end
