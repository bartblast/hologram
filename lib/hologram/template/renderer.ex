defmodule Hologram.Template.Renderer do
  alias Hologram.Template.ExpressionRenderer
  alias Hologram.Template.VirtualDOM.{Expression, TagNode, TextNode}

  def render(virtual_dom, state \\ %{})

  def render(nodes, state) when is_list(nodes) do
    Enum.map(nodes, &render(&1, state))
    |> Enum.join("")
  end

  def render(%Expression{ir: ir}, state) do
    ExpressionRenderer.render(ir, state)
  end

  def render(%TagNode{attrs: attrs, children: children, tag: tag}, state) do
    attrs_html =
      Enum.map(attrs, fn {key, value} -> " #{render_attr_name(key)}=\"#{value}\"" end)
      |> Enum.join("")

    children_html =
      Enum.map(children, fn child -> render(child, state) end)
      |> Enum.join("")

    "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
  end

  def render(%TextNode{text: text}, _state) do
    text
  end

  def render_attr_name(key) do
    case key do
      ":click" ->
        "holo-click"

      _ ->
        key
    end
  end
end
