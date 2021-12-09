# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.NilType

defimpl CallGraphBuilder, for: NilType do
  def build(_, call_graph, _, _), do: call_graph
end
