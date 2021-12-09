# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl CallGraphBuilder, for: AnonymousFunctionType do
  def build(%{params: params, body: body}, call_graph, module_defs, from_vertex) do
    call_graph = CallGraphBuilder.build(params, call_graph, module_defs, from_vertex)
    CallGraphBuilder.build(body, call_graph, module_defs, from_vertex)
  end
end
