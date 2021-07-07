defmodule Hologram.Template.ExpressionRenderer do
  alias Hologram.Template.Evaluator

  def render(ir, state) do
    Evaluator.evaluate(ir, state)
    |> to_string()
  end
end
