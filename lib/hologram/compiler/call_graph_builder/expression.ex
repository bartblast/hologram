# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Template.VDOM.Expression

defimpl CallGraphBuilder, for: Expression do
  def build(%{ir: ir}, call_graph, module_defs, from_vertex) do
    CallGraphBuilder.build(ir, call_graph, module_defs, from_vertex)
  end
end
