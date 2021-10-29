alias Hologram.Compiler.{CallGraph, Helpers}
alias Hologram.Compiler.IR.ModuleDefinition

defimpl CallGraph, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, call_graph, module_defs, _) do
    call_graph =
      if Helpers.is_page?(module_defs[module]) do
        Graph.add_edge(call_graph, module, module.layout())
      else
        Graph.add_vertex(call_graph, module)
      end

    CallGraph.build(functions, call_graph, module_defs, module)
  end
end
