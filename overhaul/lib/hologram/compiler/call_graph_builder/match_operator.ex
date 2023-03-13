# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.MatchOperator

defimpl CallGraphBuilder, for: MatchOperator do
  def build(%{right: right}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(right, module_defs, templates, from_vertex)
  end
end
