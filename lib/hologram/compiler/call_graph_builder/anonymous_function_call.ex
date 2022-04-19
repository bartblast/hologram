alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.AnonymousFunctionCall

defimpl CallGraphBuilder, for: AnonymousFunctionCall do
  def build(%{args: args}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(args, module_defs, templates, from_vertex)
  end
end
