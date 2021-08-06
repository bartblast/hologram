alias Hologram.Template.Document.Expression
alias Hologram.Template.Evaluator

defimpl Evaluator, for: Expression  do
  def evaluate(%Expression{ir: ir}, state) do
    Evaluator.evaluate(ir, state)
    |> elem(0)
  end
end
