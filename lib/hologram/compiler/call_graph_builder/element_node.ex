# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Template.VDOM.ElementNode

defimpl CallGraphBuilder, for: ElementNode do
  def build(%{attrs: attrs, children: children}, module_defs, from_vertex) do
    CallGraphBuilder.build(attrs, module_defs, from_vertex)
    CallGraphBuilder.build(children, module_defs, from_vertex)
  end
end
