defmodule Hologram.TemplateEngine.Renderer do
  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.AST.TextNode

  def render(ast, state)

  def render(%TextNode{text: text}, _state) do
    text
  end
end
