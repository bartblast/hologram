alias Hologram.Template.Document.TextNode
alias Hologram.Template.Renderer

defimpl Renderer, for: TextNode do
  def render(%{content: content}, _state) do
    content
  end
end
