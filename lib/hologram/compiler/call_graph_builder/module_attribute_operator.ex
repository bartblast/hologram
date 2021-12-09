# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ModuleAttributeOperator

defimpl CallGraphBuilder, for: ModuleAttributeOperator do
  def build(_, call_graph, _, _), do: call_graph
end
