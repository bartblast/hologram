alias Hologram.Template.Renderer

defimpl Renderer, for: List do
  def render(nodes, state, slots) do
    Enum.map(nodes, &Renderer.render(&1, state, slots))
    |> Enum.join("")
  end
end
