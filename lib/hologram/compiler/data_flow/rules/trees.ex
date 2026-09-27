defmodule Hologram.Compiler.DataFlow.Rules.Trees do
  @moduledoc false

  # What the rules modules (see Hologram.Compiler.DataFlow.Rules) build their answers with: trees
  # (see Hologram.Compiler.DataFlow.tree/0), which the analysis interns.

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow

  @doc """
  Returns what is remembered under the key in the flow context's rule cache, or the function's
  result, remembered.
  """
  @spec cached(term, DataFlow.t(), (-> value)) :: value when value: term
  def cached(key, flow, fun) do
    case PLT.get(flow.rule_cache, key) do
      {:ok, value} ->
        value

      :error ->
        value = fun.()
        PLT.put(flow.rule_cache, key, value)
        value
    end
  end

  @doc """
  Returns the struct of the module with the given fields' trees, every other field of it a
  primitive; with the struct not loaded, its other fields are not known and are a rest of
  primitives.
  """
  @spec struct_tree(module, %{optional(atom) => DataFlow.tree()}) :: DataFlow.tree()
  def struct_tree(module, overrides) do
    fields =
      if Code.ensure_loaded?(module) and function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.delete(:__struct__)
        |> Map.new(fn {key, _default} -> {key, Map.get(overrides, key, [:prim])} end)
      else
        [:prim]
        |> DataFlow.rest_fields()
        |> Map.merge(overrides)
      end

    [{:struct, module, fields}]
  end

  @doc """
  Returns the tree's shapes flattened: a struct with no fields, and what every nested tree of a
  struct, a map, a tuple, a list or a bag holds.
  """
  @spec tree_leaves(DataFlow.tree()) :: [DataFlow.shape(DataFlow.tree())]
  def tree_leaves(tree) do
    Enum.flat_map(tree, fn
      {:struct, module, fields} -> [{:struct, module, %{}} | fields_leaves(fields)]
      {:map, fields} -> fields_leaves(fields)
      {:tuple, elements} -> Enum.flat_map(elements, &tree_leaves/1)
      {kind, inner} when kind in [:bag, :list] -> tree_leaves(inner)
      shape -> [shape]
    end)
  end

  @doc """
  Returns the given trees as one, sorted, each shape once (the analysis merges the shapes of a kind
  when it interns the tree).
  """
  @spec union([DataFlow.tree()]) :: DataFlow.tree()
  def union(trees) do
    trees
    |> Enum.concat()
    |> :lists.usort()
  end

  defp fields_leaves(fields) do
    fields
    |> Map.values()
    |> Enum.flat_map(&tree_leaves/1)
  end
end
