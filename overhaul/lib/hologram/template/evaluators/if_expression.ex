alias Hologram.Compiler.IR.IfExpression
alias Hologram.Template.Evaluator

defimpl Evaluator, for: IfExpression do
  alias Hologram.Compiler.Evaluator, as: ASTEvaluator

  def evaluate(%{ast: ast}, bindings) do
    ASTEvaluator.evaluate(ast, bindings)
  end
end
