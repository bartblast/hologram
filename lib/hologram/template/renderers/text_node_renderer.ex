alias Hologram.Template.Document.TextNode
alias Hologram.Template.Renderer

defimpl Renderer, for: TextNode do
  def render(%{content: content}, _, _) do
    opts = [global: true]

    content
    |> String.replace("&lcub;", "{", opts)
    |> String.replace("&rcub;", "}", opts)
  end
end
