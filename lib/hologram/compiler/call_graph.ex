defmodule Hologram.Compiler.CallGraph do
  alias Hologram.Compiler.{Helpers, Reflection}
  alias Hologram.Compiler.IR.{FunctionCall, FunctionDefinition, IfExpression, ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.{Component, ElementNode, Expression}

  def build(module) do
    map = %{}
    graph = Graph.new
    acc = {map, graph}

    traverse(acc, module)
  end

  defp maybe_add_module_def(map, module) do
    unless map[module] || Reflection.standard_lib?(module) do
      module_def = Reflection.module_definition(module)
      Map.put(map, module, module_def)
    else
      map
    end
  end

  defp traverse(acc, ir, from_vertex \\ nil)

  defp traverse({map, graph}, module, from_vertex) when is_atom(module) do
    map = maybe_add_module_def(map, module)

    graph =
      if from_vertex do
        Graph.add_edge(graph, from_vertex, module)
      else
        graph
      end

    acc = {map, graph}

    unless from_vertex do
      Enum.reduce(map[module].functions, acc, &traverse(&2, &1))
    else
      acc
    end
  end

  defp traverse({map, graph}, %FunctionCall{module: module, function: function}, from_vertex) do
    map = maybe_add_module_def(map, module)
    to_vertex = {module, function}

    {map, graph} =
      unless Graph.has_vertex?(graph, to_vertex) do
        map[module].functions
        |> Helpers.aggregate_function_def_variants()
        |> Map.get(function)
        |> Map.get(:variants)
        |> Enum.reduce({map, graph}, &traverse(&2, &1))
      else
        {map, graph}
      end

    graph = Graph.add_edge(graph, from_vertex, to_vertex)

    {map, graph}
  end

  defp traverse({map, graph}, %FunctionDefinition{module: module, name: name, body: body}, _) do
    from_vertex = {module, name}
    Enum.reduce(body, {map, graph}, &traverse(&2, &1, from_vertex))
  end

  defp traverse(acc, _, _), do: acc

  # TODO: finish
  # defp traverse(acc, %IfExpression{condition: condition, do: do_clause, else: else_clause}, from_vertex) do
  #   traverse(acc, condition, from_vertex)
  #   |> traverse(do_clause, from_vertex)
  #   |> traverse(else_clause, from_vertex)
  # end

  # defp traverse({map, graph}, %ModuleType{module: module}, from_vertex) do
  #   map = maybe_add_module_def(map, module)

  #   to_vertex = module
  #   graph = Graph.add_vertex(graph, to_vertex)
  #   graph = Graph.add_edge(graph, from_vertex, to_vertex)


  #   traverse({map, graph}, map[module], nil)
  # end

  # defp traverse(acc, vdom_nodes, from_vertex) when is_list(vdom_nodes) do
  #   Enum.reduce(vdom_nodes, acc, &traverse(&2, &1, from_vertex))
  # end
end
