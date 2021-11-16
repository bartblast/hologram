# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.StructType

defimpl CallGraph, for: StructType do
  def build(%{data: data}, call_graph, module_defs, from_vertex) do
    CallGraph.build(data, call_graph, module_defs, from_vertex)
  end
end
