alias Hologram.Compiler.IR.AdditionOperator
alias Hologram.Template.Evaluator

defimpl Evaluator, for: AdditionOperator do
  def evaluate(%{left: left, right: right}, bindings) do
    Evaluator.evaluate(left, bindings) + Evaluator.evaluate(right, bindings)
  end
end
