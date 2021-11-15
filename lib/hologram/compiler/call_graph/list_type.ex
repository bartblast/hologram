# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.ListType

defimpl CallGraph, for: ListType do
  def build(%{data: data}, call_graph, module_defs, from_vertex) do
    CallGraph.build(data, call_graph, module_defs, from_vertex)
  end
end
