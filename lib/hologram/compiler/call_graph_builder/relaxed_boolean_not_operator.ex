# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.RelaxedBooleanNotOperator

defimpl CallGraphBuilder, for: RelaxedBooleanNotOperator do
  def build(%{value: value}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(value, module_defs, templates, from_vertex)
  end
end
