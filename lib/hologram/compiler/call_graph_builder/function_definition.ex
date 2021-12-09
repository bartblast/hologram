alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.FunctionDefinition

defimpl CallGraphBuilder, for: FunctionDefinition do
  def build(%{module: module, name: name, body: body}, call_graph, module_defs, _) do
    call_graph = Graph.add_vertex(call_graph, {module, name})
    CallGraphBuilder.build(body, call_graph, module_defs, {module, name})
  end
end
