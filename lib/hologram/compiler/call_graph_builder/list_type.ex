# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ListType

defimpl CallGraphBuilder, for: ListType do
  def build(%{data: data}, call_graph, module_defs, from_vertex) do
    CallGraphBuilder.build(data, call_graph, module_defs, from_vertex)
  end
end
