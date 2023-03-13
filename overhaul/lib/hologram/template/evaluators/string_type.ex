alias Hologram.Compiler.IR.StringType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: StringType do
  def evaluate(%{value: value}, _) do
    value
  end
end
