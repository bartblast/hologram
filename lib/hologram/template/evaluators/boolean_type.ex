alias Hologram.Compiler.IR.BooleanType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: BooleanType do
  def evaluate(%{value: value}, _) do
    value
  end
end
