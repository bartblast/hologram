defprotocol Hologram.Template.Renderer do
  def render(vdom, bindings, slots \\ nil)
end
