# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.AtomType

defimpl CallGraphBuilder, for: AtomType do
  def build(_, call_graph, _, _), do: call_graph
end
