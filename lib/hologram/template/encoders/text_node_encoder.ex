alias Hologram.Template.Document.TextNode
alias Hologram.Template.Encoder

defimpl Encoder, for: TextNode do
  def encode(%{content: content}) do
    content =
      content
      |> String.replace("\n", "\\n")
      |> String.replace("'", "\\'")
      |> String.replace("&lcub;", "{")
      |> String.replace("&rcub;", "}")

    "{ type: 'text', content: '#{content}' }"
  end
end
