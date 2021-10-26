alias Hologram.Template.{Evaluator, Renderer}
alias Hologram.Template.VDOM.ElementNode

defimpl Renderer, for: ElementNode do
  @pruned_attrs [:on_click]

  def render(%{tag: "slot"}, bindings, slots) do
    Renderer.render(slots[:default], bindings, nil)
  end

  def render(%{attrs: attrs, children: children, tag: tag}, bindings, slots) do
    attrs_html = render_attrs(attrs, bindings)
    children_html = render_children(children, bindings, slots)

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  defp render_attrs(attrs, bindings) do
    Enum.reject(attrs, fn {key, _} -> key in @pruned_attrs end)
    |> Enum.map(fn {key, spec} ->
      value = Evaluator.evaluate(spec.value, bindings)
      " #{key}=\"#{value}\""
    end)
    |> Enum.join("")
  end

  defp render_children(children, bindings, slots) do
    Enum.map(children, fn child -> Renderer.render(child, bindings, slots) end)
    |> Enum.join("")
  end
end
