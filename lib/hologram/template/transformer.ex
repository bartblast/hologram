defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.Context
  alias Hologram.Template.{ComponentTransformer, ElementNodeTransformer, EmbeddedExpressionParser, Helpers}

  def transform(nodes, %Context{} = context) when is_list(nodes) do
    Enum.reduce(nodes, [], &(&2 ++ transform(&1, context)))
  end

  def transform(node, context) when is_binary(node) do
    EmbeddedExpressionParser.parse(node, context)
  end

  def transform({tag_name, attrs, children}, context) do
    children = Enum.reduce(children, [], &(&2 ++ transform(&1, context)))

    case Helpers.tag_type(tag_name) do
      :component ->
        [ComponentTransformer.transform(tag_name, attrs, children, context)]

      :element ->
        [ElementNodeTransformer.transform(tag_name, children, attrs, context)]
    end
  end
end
