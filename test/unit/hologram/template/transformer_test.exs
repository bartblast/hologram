defmodule Hologram.Template.TransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Template.Parser
  alias Hologram.Template.Transformer
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode

  @context %Context{}

  test "text node" do
    markup = "test_text"

    result =
      Parser.parse!(markup)
      |> Transformer.transform(@context)

    expected = [%TextNode{content: "test_text"}]

    assert result == expected
  end

  test "expression node" do
    markup = "{1}"

    result =
      Parser.parse!(markup)
      |> Transformer.transform(@context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [%IntegerType{value: 1}]
        }
      }
    ]

    assert result == expected
  end

  test "element node" do
    markup = "<div><span></span></div>"

    result =
      Parser.parse!(markup)
      |> Transformer.transform(@context)

    assert [%ElementNode{children: [%ElementNode{}]}] = result
  end

  test "component node" do
    markup = "<Hologram.Test.Fixtures.PlaceholderComponent />"

    result =
      Parser.parse!(markup)
      |> Transformer.transform(@context)

    assert [%Component{}] = result
  end

  test "list of nodes" do
    markup = "<div></div><span></span>"

    result =
      Parser.parse!(markup)
      |> Transformer.transform(@context)

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
end
