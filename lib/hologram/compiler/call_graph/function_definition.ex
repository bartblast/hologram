alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.FunctionDefinition

defimpl CallGraph, for: FunctionDefinition do
  def build(%{module: module, name: name, body: body}, call_graph, module_defs, from_vertex) do
    to_vertex = {module, name}
    call_graph = Graph.add_edge(call_graph, from_vertex, to_vertex)
    from_vertex = to_vertex

    CallGraph.build(body, call_graph, module_defs, from_vertex)
  end
end
