defmodule Hologram.Template.Generator do
  alias Hologram.Template.Document.{Component, Expression, ElementNode, TextNode}
  alias Hologram.Typespecs, as: T

  alias Hologram.Template.{
    ComponentGenerator,
    ElementNodeGenerator,
    ExpressionGenerator,
    NodeListGenerator,
    TextNodeGenerator
  }

  @doc """
  Given document tree template, generates virtual DOM template JS representation,
  which can be used by the frontend runtime to re-render the DOM.

  ## Examples
      iex> generate(%ElementNode{tag: "div", children: [%TextNode{content: "test}]})
      "{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'text', content: 'test' }] }"
  """
  @spec generate(T.document_node | list(T.document_node)) :: String.t

  def generate(document_tree)

  def generate(document_tree) when is_list(document_tree) do
    NodeListGenerator.generate(document_tree)
  end

  def generate(%Component{module: module}) do
    ComponentGenerator.generate(module)
  end

  def generate(%ElementNode{attrs: attrs, children: children, tag: tag}) do
    ElementNodeGenerator.generate(tag, attrs, children)
  end

  def generate(%Expression{ir: ir}) do
    ExpressionGenerator.generate(ir)
  end

  def generate(%TextNode{content: content}) do
    TextNodeGenerator.generate(content)
  end
end
