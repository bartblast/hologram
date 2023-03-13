alias Hologram.Compiler.IR.DotOperator
alias Hologram.Template.Evaluator

defimpl Evaluator, for: DotOperator do
  def evaluate(%{left: left, right: right}, bindings) do
    left = Evaluator.evaluate(left, bindings)
    right = Evaluator.evaluate(right, bindings)

    Map.get(left, right)
  end
end
