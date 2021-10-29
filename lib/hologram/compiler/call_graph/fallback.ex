alias Hologram.Compiler.CallGraph

defimpl CallGraph, for: Any do
  def build(_, call_graph, _, _), do: call_graph
end
