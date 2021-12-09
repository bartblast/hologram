# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Template.VDOM.TextNode

defimpl CallGraphBuilder, for: TextNode do
  def build(_, call_graph, _, _), do: call_graph
end
