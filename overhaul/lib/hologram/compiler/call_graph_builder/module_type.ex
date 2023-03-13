alias Hologram.Compiler.{CallGraph, CallGraphBuilder, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl CallGraphBuilder, for: ModuleType do
  def build(%{module: module}, module_defs, templates, from_vertex) do
    unless Reflection.standard_lib?(module) do
      CallGraphBuilder.build(module_defs[module], module_defs, templates, nil)
      CallGraph.add_edge(from_vertex, module)
    end
  end
end
