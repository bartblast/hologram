defmodule Hologram.TemplateEngine.IRGenerator do
  alias Hologram.TemplateEngine.AST.TextNode

  def generate(ast)

  def generate(%TextNode{text: text}) do
    "{ type: 'text_node', text: '#{text}' }"
  end
end
