alias Hologram.Template.Renderer

defimpl Renderer, for: List do
  def render(nodes, conn, bindings, slots) do
    Enum.reduce(nodes, {"", %{}}, fn node, {html, initial_state} ->
      {node_html, node_initial_state} = Renderer.render(node, conn, bindings, slots)
      {html <> node_html, Map.merge(initial_state, node_initial_state)}
    end)
  end
end
