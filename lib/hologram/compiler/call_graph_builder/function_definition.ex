alias Hologram.Compiler.{CallGraph, CallGraphBuilder}
alias Hologram.Compiler.IR.FunctionDefinition

defimpl CallGraphBuilder, for: FunctionDefinition do
  def build(%{module: module, name: name, body: body}, module_defs, templates, _) do
    CallGraph.add_vertex({module, name})
    CallGraphBuilder.build(body, module_defs, templates, {module, name})
  end
end
