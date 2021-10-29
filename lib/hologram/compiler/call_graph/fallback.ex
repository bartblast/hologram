alias Hologram.Compiler.CallGraph

defimpl CallGraph, for: Any do
  def aggregate(_, call_graph, _), do: call_graph
end
