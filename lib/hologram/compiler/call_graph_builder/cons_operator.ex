# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ConsOperator

defimpl CallGraphBuilder, for: ConsOperator do
  def build(%{head: head, tail: tail}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(head, module_defs, templates, from_vertex)
    CallGraphBuilder.build(tail, module_defs, templates, from_vertex)
  end
end
