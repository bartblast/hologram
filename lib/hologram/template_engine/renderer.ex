defmodule Hologram.TemplateEngine.Renderer do
  alias Hologram.TemplateEngine.AST.{Expression, TagNode, TextNode}
  alias Hologram.TemplateEngine.Evaluator

  def render(ast, state)

  def render(nodes, aliases) when is_list(nodes) do
    Enum.map(nodes, fn node -> render(node, aliases) end)
    |> Enum.join("")
  end

  def render(%Expression{ast: ast}, state) do
    Evaluator.evaluate(ast, state)
    |> to_string()
  end

  def render(%TagNode{attrs: attrs, children: children, tag: tag}, state) do
    attrs_html =
      Enum.map(attrs, fn {key, value} -> " #{translate_attr(key)}=\"#{value}\"" end)
      |> Enum.join("")

    children_html =
      Enum.map(children, fn child -> render(child, state) end)
      |> Enum.join("")

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  def render(%TextNode{text: text}, _state) do
    text
  end

  defp translate_attr(key) do
    case key do
      ":click" -> "holo-click"
      _ -> key
    end
  end
end
