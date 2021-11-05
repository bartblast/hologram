# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Template.VDOM.ElementNode

defimpl CallGraph, for: ElementNode do
  def build(%{attrs: attrs, children: children}, call_graph, module_defs, from_vertex) do
    call_graph
    |> build_from_attrs(attrs, module_defs, from_vertex)
    |> build_from_children(children, module_defs, from_vertex)
  end

  defp build_from_attrs(call_graph, attrs, module_defs, from_vertex) do
    CallGraph.build(attrs, call_graph, module_defs, from_vertex)
  end

  defp build_from_children(call_graph, children, module_defs, from_vertex) do
    CallGraph.build(children, call_graph, module_defs, from_vertex)
  end
end
