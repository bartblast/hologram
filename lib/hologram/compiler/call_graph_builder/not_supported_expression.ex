# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.NotSupportedExpression

defimpl CallGraphBuilder, for: NotSupportedExpression do
  def build(_, call_graph, _, _), do: call_graph
end
