alias Hologram.Template.Renderer

defimpl Renderer, for: List do
  def render(nodes, state) do
    Enum.map(nodes, &Renderer.render(&1, state))
    |> Enum.join("")
  end
end
