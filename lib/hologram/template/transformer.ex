defmodule Hologram.Template.Transformer do
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Template.{ComponentTransformer, ElementNodeTransformer, EmbeddedExpressionParser}
  alias Hologram.Typespecs, as: T

  @doc """
  Transforms parsed markup into a document tree template.

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
  @spec transform(Saxy.SimpleForm.t(), list(%Alias{})) :: list(T.document_node())

  def transform(nodes, aliases) do
    Enum.reduce(nodes, [], &(&2 ++ transform_node(&1, aliases)))
  end

  defp transform_node(node, _) when is_binary(node) do
    EmbeddedExpressionParser.parse(node)
  end

  defp transform_node({type, attrs, children}, aliases) do
    children = Enum.reduce(children, [], &(&2 ++ transform_node(&1, aliases)))

    case determine_node_type(type, aliases) do
      :component ->
        [ComponentTransformer.transform(type, attrs, children, aliases)]

      :element ->
        [ElementNodeTransformer.transform(type, children, attrs)]
    end
  end

  defp determine_node_type(type, _) do
    first_char = String.at(type, 0)
    downcased_first_char = String.downcase(first_char)

    if first_char == downcased_first_char do
      :element
    else
      :component
    end
  end
end
