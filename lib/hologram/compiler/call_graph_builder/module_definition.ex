alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
alias Hologram.Compiler.IR.ModuleDefinition

defimpl CallGraphBuilder, for: ModuleDefinition do
  def build(%{module: module, functions: functions}, module_defs, templates, _) do
    unless CallGraph.has_vertex?(module) do
      CallGraph.add_vertex(module)
      CallGraphBuilder.build(functions, module_defs, templates, module)
      build_from_template(module, module_defs, templates)
    end
  end

  defp build_from_template(module, module_defs, templates) do
    if module_defs[module].templatable? do
      CallGraph.add_edge(module, {module, :template})
      templates[module]
      |> CallGraphBuilder.build(module_defs, templates, {module, :template})
    end
  end
end
