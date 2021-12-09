# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ModuleType
alias Hologram.Template.VDOM.Component

defimpl CallGraphBuilder, for: Component do
  def build(%{module: module, props: props, children: children}, call_graph, module_defs, from_vertex) do
    call_graph
    |> build_from_module(module, module_defs, from_vertex)
    |> build_from_props(props, module_defs, from_vertex)
    |> build_from_children(children, module_defs, from_vertex)
  end

  defp build_from_children(call_graph, children, module_defs, from_vertex) do
    CallGraphBuilder.build(children, call_graph, module_defs, from_vertex)
  end

  defp build_from_module(call_graph, module, module_defs, from_vertex) do
    %ModuleType{module: module}
    |> CallGraphBuilder.build(call_graph, module_defs, from_vertex)
  end

  defp build_from_props(call_graph, props, module_defs, from_vertex) do
    CallGraphBuilder.build(props, call_graph, module_defs, from_vertex)
  end
end
