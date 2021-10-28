alias Hologram.Compiler.{Helpers, Traverser}
alias Hologram.Compiler.IR.FunctionCall

defimpl Traverser, for: FunctionCall do
  import Hologram.Compiler.Traverser.Commons

  def traverse(%{module: module, function: function}, {map, graph}, from_vertex) do
    map = maybe_add_module_def(map, module)
    to_vertex = {module, function}

    {map, graph} =
      unless Graph.has_vertex?(graph, to_vertex) do
        map[module].functions
        |> Helpers.aggregate_function_def_variants()
        |> Map.get(function)
        |> Map.get(:variants)
        |> Enum.reduce({map, graph}, &Traverser.traverse(&1, &2))
      else
        {map, graph}
      end

    graph = Graph.add_edge(graph, from_vertex, to_vertex)

    {map, graph}
  end
end
