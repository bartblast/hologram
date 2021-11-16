# TODO: test

alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl CallGraph, for: AnonymousFunctionType do
  def build(%{params: params, body: body}, call_graph, module_defs, from_vertex) do
    call_graph = CallGraph.build(params, call_graph, module_defs, from_vertex)
    CallGraph.build(body, call_graph, module_defs, from_vertex)
  end
end
