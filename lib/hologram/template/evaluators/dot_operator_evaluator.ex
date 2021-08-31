alias Hologram.Compiler.IR.DotOperator
alias Hologram.Template.Evaluator

defimpl Evaluator, for: DotOperator  do
  def evaluate(%{left: left, right: right}, state) do
    left = Evaluator.evaluate(left, state)
    right = Evaluator.evaluate(right, state)
    
    Map.get(left, right)
  end
end
