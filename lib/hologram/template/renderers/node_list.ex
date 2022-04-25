alias Hologram.Template.Renderer

defimpl Renderer, for: List do
  def render(nodes, conn, bindings, slots) do
    Enum.map(nodes, &Renderer.render(&1, conn, bindings, slots))
    |> Enum.join("")
  end
end
