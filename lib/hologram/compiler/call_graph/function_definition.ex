alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.FunctionDefinition

defimpl CallGraph, for: FunctionDefinition do
  def build(%{module: module, name: name, body: body}, call_graph, module_defs, _) do
    call_graph = Graph.add_vertex(call_graph, {module, name})
    CallGraph.build(body, call_graph, module_defs, {module, name})
  end
end
