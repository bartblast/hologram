alias Hologram.Template.Document.Component
alias Hologram.Template.{Builder, Renderer}

defimpl Renderer, for: Component do
  def render(%{module: module, children: children}, state, _) do
    Builder.build(module)
    |> Renderer.render(state, default: children)
  end
end
