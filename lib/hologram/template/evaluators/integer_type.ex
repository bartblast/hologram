alias Hologram.Compiler.IR.IntegerType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: IntegerType do
  def evaluate(%{value: value}, _) do
    value
  end
end
