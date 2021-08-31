alias Hologram.Compiler.IR.MapType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: MapType  do
  def evaluate(%{data: data}, state) do
    Enum.map(data, fn {key, value} ->
      {Evaluator.evaluate(key, state), Evaluator.evaluate(value, state)}
    end)
    |> Enum.into(%{})
  end
end
