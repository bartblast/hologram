# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.DotOperator

defimpl CallGraph, for: DotOperator do
  def build(%{left: left, right: right}, call_graph, module_defs, from_vertex) do
    call_graph = CallGraph.build(left, call_graph, module_defs, from_vertex)
    CallGraph.build(right, call_graph, module_defs, from_vertex)
  end
end
