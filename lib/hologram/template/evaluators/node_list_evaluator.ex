alias Hologram.Template.Evaluator

defimpl Evaluator, for: List  do
  def evaluate(nodes, state) do
    Enum.reduce(nodes, "", fn node, acc ->
      result = Evaluator.evaluate(node, state)
      acc <> to_string(result)
    end)
  end
end
