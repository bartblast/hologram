alias Hologram.Template.{Evaluator, Renderer}
alias Hologram.Template.VDOM.Expression

defimpl Renderer, for: Expression do
  def render(%{ir: ir}, conn, bindings, _) do
    tuple_first_elem_ir = hd(ir.data)

    Evaluator.evaluate(tuple_first_elem_ir, bindings)
    |> to_string()
  end
end
