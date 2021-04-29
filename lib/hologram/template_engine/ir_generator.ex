defmodule Hologram.TemplateEngine.IRGenerator do
  alias Hologram.TemplateEngine.AST.{TagNode, TextNode}
  alias Hologram.TemplateEngine.Renderer

  def generate(ast)

  def generate(%TagNode{attrs: attrs, children: children, tag: tag}) do
    attrs_js =
      if Enum.any?(attrs) do
        js =
          Enum.map(attrs, fn {key, value} ->
            "'#{Renderer.render_attr_name(key)}': '#{value}'"
          end)
          |> Enum.join(", ")

        "{ #{js} }"
      else
        "{}"
      end

      children_str =
        Enum.map(children, &generate(&1))
        |> Enum.join(", ")

      children_js = "[#{children_str}]"

    "{ type: 'tag_node', tag: '#{tag}', attrs: #{attrs_js}, children: #{children_js} }"
  end

  def generate(%TextNode{text: text}) do
    "{ type: 'text_node', text: '#{text}' }"
  end

  def generate(nodes) when is_list(nodes) do
    Enum.map(nodes, &generate(&1))
  end
end
