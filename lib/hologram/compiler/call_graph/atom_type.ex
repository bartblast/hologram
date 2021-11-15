# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.AtomType

defimpl CallGraph, for: AtomType do
  def build(_, call_graph, _, _), do: call_graph
end
