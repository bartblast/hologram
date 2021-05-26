defmodule Hologram.Template.Generator do
  alias Hologram.Template.VirtualDOM.{Component, Expression, ElementNode, TextNode}
  alias Hologram.Template.{ComponentGenerator, ElementNodeGenerator, ExpressionGenerator, NodeListGenerator, TextNodeGenerator}

  def generate(virtual_dom, context \\ [module_attributes: []])

  def generate(nodes, state) when is_list(nodes) do
    NodeListGenerator.generate(nodes, state)
  end

  def generate(%Component{module: module}, context) do
    ComponentGenerator.generate(module, context)
  end

  def generate(%ElementNode{attrs: attrs, children: children, tag: tag}, context) do
    ElementNodeGenerator.generate(tag, attrs, children, context)
  end

  def generate(%Expression{ir: ir}, context) do
    ExpressionGenerator.generate(ir, context)
  end

  def generate(%TextNode{content: content}, _) do
    TextNodeGenerator.generate(content)
  end
end
