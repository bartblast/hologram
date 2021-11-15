# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.BinaryType

defimpl CallGraph, for: BinaryType do
  def build(_, call_graph, _, _), do: call_graph
end
