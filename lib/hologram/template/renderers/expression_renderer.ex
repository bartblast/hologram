defmodule Hologram.Template.ExpressionRenderer do
  alias Hologram.Template.Evaluator

  def render(ir, state) do
    tuple_first_elem_ir = hd(ir.data)
    Evaluator.evaluate(tuple_first_elem_ir, state)
    |> to_string()
  end
end
