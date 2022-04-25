alias Hologram.Runtime.TemplateStore
alias Hologram.Template.{BindingsAggregator, Renderer}
alias Hologram.Template.VDOM.Component

defimpl Renderer, for: Component do
  def render(component, conn, outer_bindings, _) do
    bindings = BindingsAggregator.aggregate(component, outer_bindings)

    TemplateStore.get!(component.module)
    |> Renderer.render(conn, bindings, default: component.children)
  end
end
