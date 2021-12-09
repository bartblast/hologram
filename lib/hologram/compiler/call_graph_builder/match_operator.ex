# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.MatchOperator

defimpl CallGraphBuilder, for: MatchOperator do
  def build(%{right: right}, call_graph, module_defs, from_vertex) do
    CallGraphBuilder.build(right, call_graph, module_defs, from_vertex)
  end
end
