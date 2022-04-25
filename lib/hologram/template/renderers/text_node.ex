alias Hologram.Template.VDOM.TextNode
alias Hologram.Template.Renderer

defimpl Renderer, for: TextNode do
  def render(%{content: content}, _conn, _bindings, _slots) do
    content
    |> String.replace("\\{", "{")
    |> String.replace("\\}", "}")
  end
end
