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

  def render(%{tag: "slot"}, bindings, slots) do
    Renderer.render(slots[:default], bindings, nil)
  end

  def render(%{attrs: attrs} = node, bindings, slots) do
    if Map.has_key?(attrs, :if) && !Evaluator.evaluate(hd(attrs.if.value), bindings) do
      ""
    else
      render_element(node, bindings, slots)
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

  defp render_children(children, bindings, slots) do
    Enum.map(children, fn child -> Renderer.render(child, bindings, slots) end)
    |> Enum.join("")
  end

  defp render_element(%{attrs: attrs, children: children, tag: tag}, bindings, slots) do
    attrs_html = render_attrs(attrs, bindings)
    children_html = render_children(children, bindings, slots)

    if Enum.member?(@void_elems, tag) do
      "<#{tag}#{attrs_html} />"
    else
      "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
    end
  end
end
