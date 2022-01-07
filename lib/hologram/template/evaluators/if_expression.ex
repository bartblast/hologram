alias Hologram.Compiler.IR.IfExpression
alias Hologram.Template.Evaluator

defimpl Evaluator, for: IfExpression do
  def evaluate(%{condition: condition, do: do_expr, else: else_expr}, bindings) do
    if Evaluator.evaluate(condition, bindings) do
      Evaluator.evaluate(do_expr, bindings)
    else
      Evaluator.evaluate(else_expr, bindings)
    end
  end
end
