# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.MatchOperator

defimpl CallGraph, for: MatchOperator do
  def build(%{left: _, right: right}, call_graph, module_defs, from_vertex) do
    CallGraph.build(right, call_graph, module_defs, from_vertex)
  end
end
