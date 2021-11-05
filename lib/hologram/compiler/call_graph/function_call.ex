# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.FunctionCall

defimpl CallGraph, for: FunctionCall do
  def build(%{module: module, function: function}, call_graph, module_defs, from_vertex) do
    CallGraph.build(module_defs[module], call_graph, module_defs)
    |> Graph.add_edge(from_vertex, {module, function})
  end
end
