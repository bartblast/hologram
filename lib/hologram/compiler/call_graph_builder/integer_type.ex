# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.IntegerType

defimpl CallGraphBuilder, for: IntegerType do
  def build(_, call_graph, _, _), do: call_graph
end
