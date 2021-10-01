alias Hologram.Template.Document.Expression
alias Hologram.Template.{Evaluator, Renderer}

defimpl Renderer, for: Expression do
  def render(%{ir: ir}, state, _) do
    tuple_first_elem_ir = hd(ir.data)

    Evaluator.evaluate(tuple_first_elem_ir, state)
    |> to_string()
  end
end
