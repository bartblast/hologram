defmodule Hologram.Template.TransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Template.VDOM.{Component, ElementNode, Expression, TextNode}

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
    html = "test_text"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    expected = [%TextNode{content: "test_text"}]

    assert result == expected
  end

  test "embedded expression" do
    html = "a{1}b"

    result =
      Parser.parse!(html)
      |> Transformer.transform(@aliases)

    expected = [
      %TextNode{content: "a"},
      %Expression{
        ir: %TupleType{
          data: [%IntegerType{value: 1}]
        }
      },
      %TextNode{content: "b"}
    ]

    assert result == expected
  end
end
