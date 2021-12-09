# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.Variable

defimpl CallGraphBuilder, for: Variable do
  def build(_, call_graph, _, _), do: call_graph
end
