# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.BinaryType

defimpl CallGraphBuilder, for: BinaryType do
  def build(_, call_graph, _, _), do: call_graph
end
