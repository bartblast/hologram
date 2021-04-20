defmodule Hologram.TemplateEngine.InterpolatorTest do
  use ExUnit.Case, async: true

  alias Hologram.TemplateEngine.AST.{Expression, TagNode, TextNode}
  alias Hologram.TemplateEngine.Interpolator
  alias Hologram.Transpiler.AST.ModuleAttribute

  test "multiple text nodes" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    result = Interpolator.interpolate(nodes)
    assert result == nodes
  end

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
        ast: %ModuleAttribute{name: :abc}
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
        ast: %ModuleAttribute{name: :abc}
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
        ast: %ModuleAttribute{name: :abc}
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
        ast: %ModuleAttribute{name: :abc}
      },
      %Expression{
        ast: %ModuleAttribute{name: :bcd}
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
        ast: %ModuleAttribute{name: :abc}
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
        ast: %ModuleAttribute{name: :abc}
      },
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttribute{name: :cde}
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
        ast: %ModuleAttribute{name: :abc}
      },
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttribute{name: :def}
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
        ast: %ModuleAttribute{name: :abc}
      },
      %TextNode{text: "bcd"},
      %Expression{
        ast: %ModuleAttribute{name: :cde}
      },
      %TextNode{text: "def"}
    ]

    assert result == expected
  end

  test "nested text node" do
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
        ast: %ModuleAttribute{name: :bcd}
      },
      %TagNode{
        attrs: %{},
        children: [
          %TextNode{text: "cde"},
          %Expression{
            ast: %ModuleAttribute{name: :def}
          }
        ],
        tag: "div"
      }
    ]

    assert result == expected
  end
end
