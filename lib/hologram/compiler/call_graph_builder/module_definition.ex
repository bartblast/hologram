alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ModuleDefinition
alias Hologram.Template.Builder

defimpl CallGraphBuilder, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, call_graph, module_defs, _) do
    case Graph.add_vertex(call_graph, module) do
      ^call_graph ->
        call_graph

      new_call_graph ->
        CallGraphBuilder.build(functions, new_call_graph, module_defs, module)
        |> build_from_template(module_defs, module)
    end
  end

  defp build_from_template(call_graph, module_defs, module) do
    if module_defs[module].templatable? do
      Builder.build(module)
      |> CallGraphBuilder.build(call_graph, module_defs, {module, :template})
    else
      call_graph
    end
  end
end
