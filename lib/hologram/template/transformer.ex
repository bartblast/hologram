defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.Context
  alias Hologram.Template.{ComponentTransformer, ElementNodeTransformer, EmbeddedExpressionParser}

  def transform(nodes, %Context{} = context) when is_list(nodes) do
    Enum.reduce(nodes, [], &(&2 ++ transform(&1, context)))
  end

  def transform({:text, str}, context) do
    EmbeddedExpressionParser.parse(str, context)
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
