# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.BooleanType

defimpl CallGraph, for: BooleanType do
  def build(_, call_graph, _, _), do: call_graph
end
