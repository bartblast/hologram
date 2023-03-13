alias Hologram.Compiler.IR.MapType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: MapType do
  def evaluate(%{data: data}, bindings) do
    Enum.map(data, fn {key, value} ->
      {Evaluator.evaluate(key, bindings), Evaluator.evaluate(value, bindings)}
    end)
    |> Enum.into(%{})
  end
end
