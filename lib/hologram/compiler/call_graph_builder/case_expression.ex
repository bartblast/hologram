alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.CaseExpression

defimpl CallGraphBuilder, for: CaseExpression do
  def build(%{condition: condition, clauses: clauses}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(condition, module_defs, templates, from_vertex)
    Enum.map(clauses, &CallGraphBuilder.build(&1.body, module_defs, templates, from_vertex))
  end
end
