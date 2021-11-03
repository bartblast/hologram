alias Hologram.Template.Renderer

defimpl Renderer, for: List do
  def render(nodes, bindings, slots) do
    Enum.map(nodes, &Renderer.render(&1, bindings, slots))
    |> Enum.join("")
  end
end
