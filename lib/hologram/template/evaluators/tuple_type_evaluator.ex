alias Hologram.Compiler.IR.TupleType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: TupleType  do
  def evaluate(%{data: data}, state) do
    Enum.map(data, &Evaluator.evaluate(&1, state))
    |> List.to_tuple()
  end
end
