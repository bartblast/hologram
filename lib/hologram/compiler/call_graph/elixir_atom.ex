# TODO: test

alias Hologram.Compiler.CallGraph

defimpl CallGraph, for: Atom do
  def build(_, call_graph, _, _), do: call_graph
end
