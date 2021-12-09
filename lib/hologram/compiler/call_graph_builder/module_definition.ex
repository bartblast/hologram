alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
alias Hologram.Compiler.IR.ModuleDefinition
alias Hologram.Template.Builder

defimpl CallGraphBuilder, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, module_defs, _) do
    unless CallGraph.has_vertex?(module) do
      CallGraph.add_vertex(module)
      CallGraphBuilder.build(functions, module_defs, module)
      build_from_template(module_defs, module)
    end
  end

  defp build_from_template(module_defs, module) do
    if module_defs[module].templatable? do
      Builder.build(module)
      |> CallGraphBuilder.build(module_defs, {module, :template})
    end
  end
end
