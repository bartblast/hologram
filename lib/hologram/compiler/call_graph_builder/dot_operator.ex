# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.DotOperator

defimpl CallGraphBuilder, for: DotOperator do
  def build(%{left: left, right: right}, module_defs, from_vertex) do
    CallGraphBuilder.build(left, module_defs, from_vertex)
    CallGraphBuilder.build(right, module_defs, from_vertex)
  end
end
