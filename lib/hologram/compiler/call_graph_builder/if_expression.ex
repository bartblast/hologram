alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.IfExpression

defimpl CallGraphBuilder, for: IfExpression do
  def build(%{condition: condition, do: do_clause, else: else_clause}, module_defs, from_vertex) do
    CallGraphBuilder.build(condition, module_defs, from_vertex)
    CallGraphBuilder.build(do_clause, module_defs, from_vertex)
    CallGraphBuilder.build(else_clause, module_defs, from_vertex)
  end
end
