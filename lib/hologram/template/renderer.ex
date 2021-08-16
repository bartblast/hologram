defprotocol Hologram.Template.Renderer do
  def render(document, state, slots \\ nil)
end
