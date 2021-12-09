# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.BooleanType

defimpl CallGraphBuilder, for: BooleanType do
  def build(_, call_graph, _, _), do: call_graph
end
