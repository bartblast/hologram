# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Template.VDOM.Expression

defimpl CallGraphBuilder, for: Expression do
  def build(%{ir: ir}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(ir, module_defs, templates, from_vertex)
  end
end
