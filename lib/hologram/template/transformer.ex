defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.Context
  alias Hologram.Template.{ComponentTransformer, ElementNodeTransformer, EmbeddedExpressionParser}

  @doc """
  Transforms parsed markup into a VDOM template.

  ## Examples
      iex> transform([{"div", [{"class", "{1}"}, {"id", "some-id"}], ["some-text-{2}"]}])
      [
        %ElementNode{
          attrs: %{
            "class" => %Expression{
              ir: %TupleType{
                data: [%IntegerType{value: 1}]
              }
            },
            "id" => "some-id"
          },
          children: [
            %TextNode{content: "some-text-"},
            %Expression{
              ir: %TupleType{
                data: [%IntegerType{value: 2}]
              }
            }
          ],
          tag: "div"
        }
      ]
  """

  def transform(nodes, %Context{} = context) do
    Enum.reduce(nodes, [], &(&2 ++ transform_node(&1, context)))
  end

  defp transform_node(node, context) when is_binary(node) do
    EmbeddedExpressionParser.parse(node, context)
  end

  defp transform_node({type, attrs, children}, context) do
    children = Enum.reduce(children, [], &(&2 ++ transform_node(&1, context)))

    case determine_node_type(type) do
      :component ->
        [ComponentTransformer.transform(type, attrs, children, context)]

      :element ->
        [ElementNodeTransformer.transform(type, children, attrs, context)]
    end
  end

  defp determine_node_type(type) do
    first_char = String.at(type, 0)
    downcased_first_char = String.downcase(first_char)

    if first_char == downcased_first_char do
      :element
    else
      :component
    end
  end
end
