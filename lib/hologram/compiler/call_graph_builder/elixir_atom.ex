# TODO: test

alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: Atom do
  def build(_, call_graph, _, _), do: call_graph
end
