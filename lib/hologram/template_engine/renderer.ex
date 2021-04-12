defmodule Hologram.TemplateEngine.Renderer do
  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.AST.TextNode

  def render(ast, state)

  def render(%TagNode{attrs: attrs, children: children, tag: tag}, state) do
    attrs_html =
      Enum.map(attrs, fn {key, value} -> " #{key}=\"#{value}\"" end)
      |> Enum.join("")

    children_html =
      Enum.map(children, fn child -> render(child, state) end)
      |> Enum.join("")

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  def render(%TextNode{text: text}, _state) do
    text
  end
end
