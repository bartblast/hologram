alias Hologram.Template.Evaluator

defimpl Evaluator, for: List do
  def evaluate(nodes, bindings) do
    Enum.reduce(nodes, "", fn node, acc ->
      result = Evaluator.evaluate(node, bindings)
      acc <> to_string(result)
    end)
  end
end
