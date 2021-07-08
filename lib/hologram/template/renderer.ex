defmodule Hologram.Template.Renderer do
  alias Hologram.Template.{
    ComponentRenderer,
    ExpressionRenderer,
    NodeListRenderer,
    ElementNodeRenderer
  }

  alias Hologram.Template.Document.{Component, Expression, ElementNode, TextNode}

  def render(virtual_dom, state \\ %{})

  def render(nodes, state) when is_list(nodes) do
    NodeListRenderer.render(nodes, state)
  end

  def render(%Component{module: module}, state) do
    ComponentRenderer.render(module, state)
  end

  def render(%ElementNode{attrs: attrs, children: children, tag: tag}, state) do
    ElementNodeRenderer.render(tag, attrs, children, state)
  end

  def render(%Expression{ir: ir}, state) do
    ExpressionRenderer.render(ir, state)
  end

  def render(%TextNode{content: content}, _state) do
    content
  end
end
