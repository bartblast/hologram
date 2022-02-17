# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.UnaryNegativeOperator

defimpl CallGraphBuilder, for: UnaryNegativeOperator do
  def build(%{value: value}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(value, module_defs, templates, from_vertex)
  end
end
