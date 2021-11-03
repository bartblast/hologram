alias Hologram.Template.Evaluator

defimpl Evaluator, for: Any do
  def evaluate(value, _), do: value
end
