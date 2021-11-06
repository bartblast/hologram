alias Hologram.Compiler.{CallGraph, Reflection}
alias Hologram.Compiler.IR.FunctionCall

defimpl CallGraph, for: FunctionCall do
  def build(%{module: module, function: function}, call_graph, module_defs, from_vertex) do
    if Reflection.standard_lib?(module) do
      call_graph
    else
      CallGraph.build(module_defs[module], call_graph, module_defs)
      |> Graph.add_edge(from_vertex, {module, function})
    end
  end
end
