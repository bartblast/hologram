alias Hologram.Template.Document.ElementNode
alias Hologram.Template.{Evaluator, Renderer}

defimpl Renderer, for: ElementNode do
  @pruned_attrs [:on_click]

  def render(%{tag: "slot"}, state, slots) do
    Renderer.render(slots[:default], state, nil)
  end

  def render(%{attrs: attrs, children: children, tag: tag}, state, _) do
    attrs_html = render_attrs(attrs, state)
    children_html = render_children(children, state)

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  defp render_attrs(attrs, state) do
    Enum.reject(attrs, fn {key, _} -> key in @pruned_attrs end)
    |> Enum.map(fn {key, spec} ->
      value = Evaluator.evaluate(spec.value, state)
      " #{key}=\"#{value}\""
    end)
    |> Enum.join("")
  end

  defp render_children(children, state) do
    Enum.map(children, fn child -> Renderer.render(child, state) end)
    |> Enum.join("")
  end
end
