# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.RelaxedBooleanAndOperator

defimpl CallGraphBuilder, for: RelaxedBooleanAndOperator do
  def build(%{left: left, right: right}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(left, module_defs, templates, from_vertex)
    CallGraphBuilder.build(right, module_defs, templates, from_vertex)
  end
end
