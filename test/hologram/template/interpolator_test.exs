defmodule Hologram.Template.InterpolatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Template.VirtualDOM.{Expression, ElementNode, TextNode}
  alias Hologram.Template.Interpolator

  test "text" do
    nodes = [
      %TextNode{content: "test"}
    ]

    result = Interpolator.interpolate(nodes)
    assert result == nodes
  end

  test "expression" do
    nodes = [
      %TextNode{content: "{{ @abc }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      }
    ]

    assert result == expected
  end

  test "text, expression" do
    nodes = [
      %TextNode{content: "bcd{{ @abc }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{content: "bcd"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      }
    ]

    assert result == expected
  end

  test "expression, text" do
    nodes = [
      %TextNode{content: "{{ @abc }}bcd"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{content: "bcd"}
    ]

    assert result == expected
  end

  test "expression, expression" do
    nodes = [
      %TextNode{content: "{{ @abc }}{{ @bcd }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      },
      %Expression{
        ir: %ModuleAttributeOperator{name: :bcd}
      }
    ]

    assert result == expected
  end

  test "text, expression, text" do
    nodes = [
      %TextNode{content: "cde{{ @abc }}bcd"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{content: "cde"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{content: "bcd"}
    ]

    assert result == expected
  end

  test "expression, text, expression" do
    nodes = [
      %TextNode{content: "{{ @abc }}bcd{{ @cde }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{content: "bcd"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :cde}
      }
    ]

    assert result == expected
  end

  test "text, expression, text, expression" do
    nodes = [
      %TextNode{content: "cde{{ @abc }}bcd{{ @def }}"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{content: "cde"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{content: "bcd"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :def}
      }
    ]

    assert result == expected
  end

  test "expression, text, expression, text" do
    nodes = [
      %TextNode{content: "{{ @abc }}bcd{{ @cde }}def"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %Expression{
        ir: %ModuleAttributeOperator{name: :abc}
      },
      %TextNode{content: "bcd"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :cde}
      },
      %TextNode{content: "def"}
    ]

    assert result == expected
  end

  test "multiple nodes" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    result = Interpolator.interpolate(nodes)
    assert result == nodes
  end

  test "nested node" do
    nodes = [
      %TextNode{content: "abc{{ @bcd }}"},
      %ElementNode{
        tag: "div",
        attrs: %{},
        children: [
          %TextNode{content: "cde{{ @def }}"}
        ]
      }
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{content: "abc"},
      %Expression{
        ir: %ModuleAttributeOperator{name: :bcd}
      },
      %ElementNode{
        attrs: %{},
        children: [
          %TextNode{content: "cde"},
          %Expression{
            ir: %ModuleAttributeOperator{name: :def}
          }
        ],
        tag: "div"
      }
    ]

    assert result == expected
  end
end
