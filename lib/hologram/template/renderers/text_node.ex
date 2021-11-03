alias Hologram.Template.VDOM.TextNode
alias Hologram.Template.Renderer

defimpl Renderer, for: TextNode do
  def render(%{content: content}, _, _) do
    content
    |> String.replace("&lcub;", "{")
    |> String.replace("&rcub;", "}")
  end
end
