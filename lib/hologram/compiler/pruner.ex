defmodule Hologram.Compiler.Pruner do
  alias Hologram.Compiler.{Helpers, Reflection}
  alias Hologram.Compiler.IR.{FunctionCall, FunctionDefinition, TupleType}
  alias Hologram.Template
  alias Hologram.Template.Document.{Component, ElementNode, Expression}
  alias Hologram.Typespecs, as: T

  @doc """
  Prunes unused modules and functions.
  """
  @spec prune(T.module_definitions_map, module()) :: T.module_definitions_map()

  def prune(module_defs_map, module) do
    find_used_functions(module_defs_map, module)
    |> prune_unused_functions(module_defs_map)
    |> prune_unused_modules()
  end

  defp find_used_functions(module_defs_map, module, acc \\ MapSet.new()) do
    acc
    |> traverse_function_defs(module_defs_map, {module, :action})
    |> traverse_template(module_defs_map, module)
  end

  defp get_function_defs(module_defs_map, module, function) do
    if module_defs_map[module] do
      module_defs_map[module].functions
      |> Enum.filter(&(&1.name == function))
    else
      []
    end
  end

  defp get_module_used_functions(module_def, used_functions) do
    Enum.reduce(module_def.functions, [], fn function_def, acc ->
      # The function call may use default parameter values,
      # so we include all functions matching the name (regardless of their arity).
      # DEFER: include only functions with matching arity
      if {module_def.module, function_def.name} in used_functions do
        acc ++ [function_def]
      else
        acc
      end
    end)
  end

  defp prune_unused_functions(used_functions, module_defs_map) do
    Enum.map(module_defs_map, fn {module, module_def} ->
      functions = get_module_used_functions(module_def, used_functions)
      {module, %{module_def | functions: functions}}
    end)
    |> Enum.into(%{})
  end

  defp prune_unused_modules(module_defs_map) do
    Enum.filter(module_defs_map, fn {_, module_def} ->
      Enum.any?(module_def.functions)
    end)
    |> Enum.into(%{})
  end

  # DEFER: match function arity
  defp traverse_function_defs(acc, module_defs_map, {module, function}) do
    unless MapSet.member?(acc, {module, function}) do
      acc = MapSet.put(acc, {module, function})

      get_function_defs(module_defs_map, module, function)
      |> Enum.reduce(acc, &traverse_function_defs(&2, module_defs_map, &1))
    else
      acc
    end
  end

  defp traverse_function_defs(acc, module_defs_map, %FunctionDefinition{body: body}) do
    Enum.reduce(body, acc, &traverse_function_defs(&2, module_defs_map, &1))
  end

  defp traverse_function_defs(acc, module_defs_map, %FunctionCall{module: module, function: function}) do
    traverse_function_defs(acc, module_defs_map, {module, function})
  end

  # DEFER: traverse nested code blocks
  defp traverse_function_defs(acc, _, _), do: acc

  defp traverse_template(acc, module_defs_map, module) when is_atom(module) do
    spec = {module, :template}

    unless MapSet.member?(acc, spec) || !Reflection.has_template?(module) do
      acc =
        MapSet.put(acc, spec)
        |> traverse_function_defs(module_defs_map, spec)

      acc =
        if Helpers.is_page?(module_defs_map[module]) do
          find_used_functions(module_defs_map, module.layout(), acc)
        else
          acc
        end

      document = Template.Builder.build(module)
      traverse_template(acc, module_defs_map, document)
    else
      acc
    end
  end

  defp traverse_template(acc, module_defs_map, nodes) when is_list(nodes) do
    Enum.reduce(nodes, acc, &traverse_template(&2, module_defs_map, &1))
  end

  defp traverse_template(acc, module_defs_map, %Component{module: module, props: props, children: children}) do
    acc = traverse_template(acc, module_defs_map, module)

    acc =
      Enum.reduce(props, acc, fn {_, value}, acc ->
        traverse_template(acc, module_defs_map, value)
      end)

    Enum.reduce(children, acc, &traverse_template(&2, module_defs_map, &1))
  end

  defp traverse_template(acc, module_defs_map, %ElementNode{attrs: attrs, children: children}) do
    acc =
      Enum.reduce(attrs, acc, fn {_, %{value: value}}, acc ->
        traverse_template(acc, module_defs_map, value)
      end)

    Enum.reduce(children, acc, &traverse_template(&2, module_defs_map, &1))
  end

  defp traverse_template(acc, module_defs_map, %Expression{ir: ir}) do
    traverse_template(acc, module_defs_map, ir)
  end

  defp traverse_template(acc, module_defs_map, %FunctionCall{} = function_call) do
    traverse_function_defs(acc, module_defs_map, function_call)
  end

  defp traverse_template(acc, module_defs_map, %TupleType{data: data}) do
    Enum.reduce(data, acc, &traverse_template(&2, module_defs_map, &1))
  end

  defp traverse_template(acc, _, _), do: acc
end
