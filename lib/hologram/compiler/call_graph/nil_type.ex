# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.NilType

defimpl CallGraph, for: NilType do
  def build(_, call_graph, _, _), do: call_graph
end
