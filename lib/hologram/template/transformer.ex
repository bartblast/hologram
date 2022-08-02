defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.ComponentTransformer
  alias Hologram.Template.ElementNodeTransformer
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode

  def transform(nodes, %Context{} = context) when is_list(nodes) do
    Enum.reduce(nodes, [], &(&2 ++ transform(&1, context)))
  end

  def transform({:text, content}, _context) do
    [%TextNode{content: content}]
  end

  def transform({:expression, code}, context) do
    [%Expression{ir: Reflection.ir(code, context)}]
  end

  def transform({type, tag_name, attrs, children}, context) do
    children = Enum.reduce(children, [], &(&2 ++ transform(&1, context)))

    case type do
      :component ->
        [ComponentTransformer.transform(tag_name, attrs, children, context)]

      :element ->
        [ElementNodeTransformer.transform(tag_name, children, attrs, context)]
    end
  end
end
