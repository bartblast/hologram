alias Hologram.Template.{Evaluator, Renderer}
alias Hologram.Template.VDOM.{ElementNode, Expression}

defimpl Renderer, for: ElementNode do
  alias Hologram.Compiler.IR.TupleType

  @pruned_attrs [
    :if,
    :"on:blur",
    :"on:change",
    :"on:click",
    :"on:pointer_down",
    :"on:pointer_up",
    :"on:submit",
    :"on:transition_end"
  ]

  # see: https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  def render(%{tag: "slot"}, conn, _, {slot_bindings, default: default_slot}) do
    Renderer.render(default_slot, conn, slot_bindings, nil)
  end

  def render(%{attrs: attrs} = node, conn, bindings, slots) do
    if Map.has_key?(attrs, :if) && !Evaluator.evaluate(hd(attrs.if.value), bindings) do
      {"", %{}}
    else
      render_element(node, conn, bindings, slots)
    end
  end

  defp render_attr(%{value: nil}, key, _bindings) do
    " #{key}"
  end

  defp render_attr(%{value: [%Expression{ir: %TupleType{data: [expr]}}]}, key, bindings) do
    value = Evaluator.evaluate(expr, bindings)

    case value do
      nil ->
        " #{key}"

      false ->
        ""

      value ->
        " #{key}=\"#{value}\""
    end
  end

  defp render_attr(%{value: value}, key, bindings) do
    value = Evaluator.evaluate(value, bindings)
    " #{key}=\"#{value}\""
  end

  defp render_attrs(attrs, bindings) do
    Enum.reject(attrs, fn {key, _} -> key in @pruned_attrs end)
    |> Enum.map(fn {key, spec} -> render_attr(spec, key, bindings) end)
    |> Enum.join("")
  end

  defp render_children(children, conn, bindings, slots) do
    Enum.reduce(children, {"", %{}}, fn child, {html, initial_state} ->
      {child_html, child_initial_state} = Renderer.render(child, conn, bindings, slots)
      {html <> child_html, Map.merge(initial_state, child_initial_state)}
    end)
  end

  defp render_element(%{attrs: attrs, children: children, tag: tag}, conn, bindings, slots) do
    attrs_html = render_attrs(attrs, bindings)
    {children_html, children_initial_state} = render_children(children, conn, bindings, slots)

    html =
      if Enum.member?(@void_elems, tag) do
        "<#{tag}#{attrs_html} />"
      else
        "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
      end

    {html, children_initial_state}
  end
end
