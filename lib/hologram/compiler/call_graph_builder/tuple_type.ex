# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.TupleType

defimpl CallGraphBuilder, for: TupleType do
  def build(%{data: data}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(data, module_defs, templates, from_vertex)
  end
end
