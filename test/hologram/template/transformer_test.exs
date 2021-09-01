defmodule Hologram.Template.TransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Template.Document.{Component, Expression, ElementNode, TextNode}

  @aliases []

  test "list of nodes" do
    html = "<div></div><span></span>"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    expected = [
      %ElementNode{
        attrs: %{},
        children: [],
        tag: "div"
      },
      %ElementNode{
        attrs: %{},
        children: [],
        tag: "span"
      }
    ]

    assert result == expected
  end

  test "component node" do
    html = "<Hologram.Test.Fixtures.PlaceholderComponent />"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    assert [%Component{}] = result
  end

  test "element node" do
    html = "<div><span></span></div>"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    assert [%ElementNode{children: [%ElementNode{}]}] = result
  end

  test "text node" do
    html = "<div>test_text</div>"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    expected = [
      %ElementNode{
        attrs: %{},
        children: [
          %TextNode{content: "test_text"}
        ],
        tag: "div"
      }
    ]

    assert result == expected
  end

  test "expression interpolation in attrs" do
    html = """
    <div attr_1="value_1" attr_2={@value_2} attr_3="value_3"></div>
    """

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    expected = [
      %ElementNode{
        attrs: %{
          attr_1: %{value: "value_1", modifiers: []},
          attr_2: %{
            value: %Expression{
              ir: %TupleType{
                data: [%ModuleAttributeOperator{name: :value_2}]
              }
            },
            modifiers: []
          },
          attr_3: %{value: "value_3", modifiers: []}
        },
        children: [],
        tag: "div"
      }
    ]

    assert result == expected
  end

  test "expression interpolation in text node" do
    html = "test_1{@x1}test_2"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    expected = [
      %TextNode{content: "test_1"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :x1}]
        }
      },
      %TextNode{content: "test_2"}
    ]

    assert result == expected
  end
end
