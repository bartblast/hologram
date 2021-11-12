alias Hologram.Compiler.IR.ListType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: ListType do
  def evaluate(%{data: data}, bindings) do
    Enum.map(data, &Evaluator.evaluate(&1, bindings))
  end
end
