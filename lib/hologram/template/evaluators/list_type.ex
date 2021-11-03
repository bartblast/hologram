alias Hologram.Compiler.IR.ListType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: ListType do
  def evaluate(%{data: data}, state) do
    Enum.map(data, &Evaluator.evaluate(&1, state))
  end
end
