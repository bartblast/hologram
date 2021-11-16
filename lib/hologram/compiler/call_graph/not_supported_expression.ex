# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.NotSupportedExpression

defimpl CallGraph, for: NotSupportedExpression do
  def build(_, call_graph, _, _), do: call_graph
end
