# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.ModuleAttributeOperator

defimpl CallGraph, for: ModuleAttributeOperator do
  def build(_, call_graph, _, _), do: call_graph
end
