# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Template.VDOM.TextNode

defimpl CallGraph, for: TextNode do
  def build(_, call_graph, _, _), do: call_graph
end
