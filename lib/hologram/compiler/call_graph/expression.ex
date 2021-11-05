# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Template.VDOM.Expression

defimpl CallGraph, for: Expression do
  def build(%{ir: ir}, call_graph, module_defs, from_vertex) do
    CallGraph.build(ir, call_graph, module_defs, from_vertex)
  end
end
