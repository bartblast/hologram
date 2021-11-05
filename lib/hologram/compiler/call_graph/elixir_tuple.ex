# TODO: test

alias Hologram.Compiler.CallGraph

defimpl CallGraph, for: Tuple do
  def build(tuple, call_graph, module_defs, from_vertex) do
    tuple
    |> Tuple.to_list()
    |> CallGraph.build(call_graph, module_defs, from_vertex)
  end
end
