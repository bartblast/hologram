alias Hologram.Template.VDOM.Expression
alias Hologram.Template.Evaluator

defimpl Evaluator, for: Expression do
  def evaluate(%Expression{ir: ir}, bindings) do
    Evaluator.evaluate(ir, bindings)
    |> elem(0)
  end
end
