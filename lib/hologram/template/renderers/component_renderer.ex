alias Hologram.Template.Document.Component
alias Hologram.Template.{BindingsAggregator, Builder, Renderer}

defimpl Renderer, for: Component do
  def render(component, outer_bindings, _) do
    bindings = BindingsAggregator.aggregate(component, outer_bindings)

    Builder.build(component.module)
    |> Renderer.render(bindings, default: component.children)
  end
end
