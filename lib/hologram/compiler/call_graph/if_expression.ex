alias Hologram.Compiler.CallGraph
alias Hologram.Compiler.IR.IfExpression

defimpl CallGraph, for: IfExpression do
  def build(%{condition: condition, do: do_clause, else: else_clause}, call_graph, module_defs, from_vertex) do
    call_graph
    |> build_from_condition(condition, module_defs, from_vertex)
    |> build_from_do_clause(do_clause, module_defs, from_vertex)
    |> build_from_else_clause(else_clause, module_defs, from_vertex)
  end

  defp build_from_condition(call_graph, condition, module_defs, from_vertex) do
    CallGraph.build(condition, call_graph, module_defs, from_vertex)
  end

  defp build_from_do_clause(call_graph, do_clause, module_defs, from_vertex) do
    CallGraph.build(do_clause, call_graph, module_defs, from_vertex)
  end

  defp build_from_else_clause(call_graph, else_clause, module_defs, from_vertex) do
    CallGraph.build(else_clause, call_graph, module_defs, from_vertex)
  end
end
