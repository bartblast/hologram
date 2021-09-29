defmodule Hologram.Template.TransformerTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Template.Document.{Component, ElementNode, TextNode}

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
end
