# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.IntegerType

defimpl CallGraph, for: IntegerType do
  def build(_, call_graph, _, _), do: call_graph
end
