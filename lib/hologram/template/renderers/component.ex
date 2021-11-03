alias Hologram.Template.{BindingsAggregator, Builder, Renderer}
alias Hologram.Template.VDOM.Component

defimpl Renderer, for: Component do
  def render(component, outer_bindings, _) do
    bindings = BindingsAggregator.aggregate(component, outer_bindings)

    Builder.build(component.module)
    |> Renderer.render(bindings, default: component.children)
  end
end
