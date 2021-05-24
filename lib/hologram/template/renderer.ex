defmodule Hologram.Template.Renderer do
  alias Hologram.Template.{ExpressionRenderer, NodeListRenderer, ElementNodeRenderer}
  alias Hologram.Template.VirtualDOM.{Expression, ElementNode, TextNode}

  def render(virtual_dom, state \\ %{})

  def render(nodes, state) when is_list(nodes) do
    NodeListRenderer.render(nodes, state)
  end

  def render(%Expression{ir: ir}, state) do
    ExpressionRenderer.render(ir, state)
  end

  def render(%ElementNode{attrs: attrs, children: children, tag: tag}, state) do
    ElementNodeRenderer.render(tag, attrs, children, state)
  end

  def render(%TextNode{text: text}, _state) do
    text
  end
end
