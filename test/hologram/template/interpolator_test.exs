defmodule Hologram.Template.InterpolatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.ModuleAttributeOperator
  alias Hologram.Template.AST.{Expression, TagNode, TextNode}
  alias Hologram.Template.Interpolator

  test "text" do
    nodes = [
      %TextNode{text: "test"}
    ]

    result = Interpolator.interpolate(nodes)
    assert result == nodes
  end

  test "expression" do
    nodes = [
      %TextNode{text: "{{ @abc }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      }
    ]

    assert result == expected
  end

  test "text, expression" do
    nodes = [
      %TextNode{text: "bcd{{ @abc }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      }
    ]

    assert result == expected
  end

  test "expression, text" do
    nodes = [
      %TextNode{text: "{{ @abc }}bcd"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{text: "bcd"}
    ]

    assert result == expected
  end

  test "expression, expression" do
    nodes = [
      %TextNode{text: "{{ @abc }}{{ @bcd }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      },
      %Expression{
        ast: %ModuleAttributeOperator{name: :bcd}
      }
    ]

    assert result == expected
  end

  test "text, expression, text" do
    nodes = [
      %TextNode{text: "cde{{ @abc }}bcd"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{text: "cde"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{text: "bcd"}
    ]

    assert result == expected
  end

  test "expression, text, expression" do
    nodes = [
      %TextNode{text: "{{ @abc }}bcd{{ @cde }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :cde}
      }
    ]

    assert result == expected
  end

  test "text, expression, text, expression" do
    nodes = [
      %TextNode{text: "cde{{ @abc }}bcd{{ @def }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{text: "cde"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :def}
      }
    ]

    assert result == expected
  end

  test "expression, text, expression, text" do
    nodes = [
      %TextNode{text: "{{ @abc }}bcd{{ @cde }}def"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ast: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :cde}
      },
      %TextNode{text: "def"}
    ]

    assert result == expected
  end

  test "multiple nodes" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    result = Interpolator.interpolate(nodes)
    assert result == nodes
  end

  test "nested node" do
    nodes = [
      %TextNode{text: "abc{{ @bcd }}"},
      %TagNode{
        tag: "div",
        attrs: %{},
        children: [
          %TextNode{text: "cde{{ @def }}"}
        ]
      }
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{text: "abc"},
      %Expression{
        ast: %ModuleAttributeOperator{name: :bcd}
      },
      %TagNode{
        attrs: %{},
        children: [
          %TextNode{text: "cde"},
          %Expression{
            ast: %ModuleAttributeOperator{name: :def}
          }
        ],
        tag: "div"
      }
    ]

    assert result == expected
  end
end
