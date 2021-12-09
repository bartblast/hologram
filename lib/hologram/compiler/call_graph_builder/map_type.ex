# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.MapType

defimpl CallGraphBuilder, for: MapType do
  def build(%{data: data}, call_graph, module_defs, from_vertex) do
    CallGraphBuilder.build(data, call_graph, module_defs, from_vertex)
  end
end
