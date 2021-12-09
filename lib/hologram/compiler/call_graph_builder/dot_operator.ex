# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.DotOperator

defimpl CallGraphBuilder, for: DotOperator do
  def build(%{left: left, right: right}, call_graph, module_defs, from_vertex) do
    call_graph = CallGraphBuilder.build(left, call_graph, module_defs, from_vertex)
    CallGraphBuilder.build(right, call_graph, module_defs, from_vertex)
  end
end
