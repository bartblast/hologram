# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl CallGraphBuilder, for: AnonymousFunctionType do
  def build(%{params: params, body: body}, module_defs, from_vertex) do
    CallGraphBuilder.build(params, module_defs, from_vertex)
    CallGraphBuilder.build(body, module_defs, from_vertex)
  end
end
