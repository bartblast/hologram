alias Hologram.Template.Document.Component
alias Hologram.Template.{Builder, Renderer}

defimpl Renderer, for: Component do
  def render(%{module: module}, state) do
    Builder.build(module)
    |> Renderer.render(state)
  end
end
