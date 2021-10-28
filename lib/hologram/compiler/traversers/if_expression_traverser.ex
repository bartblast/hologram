alias Hologram.Compiler.IR.IfExpression
alias Hologram.Compiler.Traverser

defimpl Traverser, for: IfExpression do
  def traverse(%{condition: condition, do: do_clause, else: else_clause}, acc, from_vertex) do
    acc = Traverser.traverse(condition, acc, from_vertex)
    acc = Traverser.traverse(do_clause, acc, from_vertex)
    Traverser.traverse(else_clause, acc, from_vertex)
  end
end
