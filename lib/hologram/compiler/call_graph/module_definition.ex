alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.ModuleDefinition

defimpl CallGraph, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, call_graph, module_defs, _) do
    from_vertex = module
    call_graph = Graph.add_vertex(call_graph, from_vertex)

    CallGraph.build(functions, call_graph, module_defs, from_vertex)
  end
end
