# TODO: test

alias Hologram.Compiler.CallGraph

defimpl CallGraph, for: Map do
  def build(map, call_graph, module_defs, from_vertex) do
    map
    |> Map.to_list()
    |> CallGraph.build(call_graph, module_defs, from_vertex)
  end
end
