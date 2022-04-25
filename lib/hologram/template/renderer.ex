defprotocol Hologram.Template.Renderer do
  def render(vdom, conn, bindings, slots \\ nil)
end
