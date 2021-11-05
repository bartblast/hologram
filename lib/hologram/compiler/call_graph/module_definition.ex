alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.ModuleDefinition

defimpl CallGraph, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, call_graph, module_defs, _) do
    case Graph.add_vertex(call_graph, module) do
      ^call_graph ->
        call_graph

      new_call_graph ->
        CallGraph.build(functions, new_call_graph, module_defs, module)
    end
  end
end
