defmodule Hologram.Template.InterpolatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeOperator}
  alias Hologram.Template.VirtualDOM.{Expression, ElementNode, TextNode}
  alias Hologram.Template.Interpolator

  describe "text node" do
    test "text" do
      node = %TextNode{content: "test"}
      result = Interpolator.interpolate(node)

      assert result == [node]
    end

    test "expression" do
      node = %TextNode{content: "{{ @abc }}"}
      result = Interpolator.interpolate(node)

      expected = [
        %Expression{
          ir: %ModuleAttributeOperator{name: :abc}
        }
      ]

      assert result == expected
    end

    test "text, expression" do
      node = %TextNode{content: "bcd{{ @abc }}"}
      result = Interpolator.interpolate(node)

      expected = [
        %TextNode{content: "bcd"},
        %Expression{
          ir: %ModuleAttributeOperator{name: :abc}
        }
      ]

      assert result == expected
    end

    test "expression, text" do
      node = %TextNode{content: "{{ @abc }}bcd"}
      result = Interpolator.interpolate(node)

      expected = [
        %Expression{
          ir: %ModuleAttributeOperator{name: :abc}
        },
        %TextNode{content: "bcd"}
      ]

      assert result == expected
    end

    test "expression, expression" do
      node = %TextNode{content: "{{ @abc }}{{ @bcd }}"}
      result = Interpolator.interpolate(node)

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
      node = %TextNode{content: "cde{{ @abc }}bcd"}
      result = Interpolator.interpolate(node)

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
      node = %TextNode{content: "{{ @abc }}bcd{{ @cde }}"}
      result = Interpolator.interpolate(node)

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
      node = %TextNode{content: "cde{{ @abc }}bcd{{ @def }}"}
      result = Interpolator.interpolate(node)

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
      node = %TextNode{content: "{{ @abc }}bcd{{ @cde }}def"}
      result = Interpolator.interpolate(node)

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
  end

  describe "element node" do
    test "doesn't have children and attributes" do
      node = %ElementNode{children: [], attrs: %{}}
      result = Interpolator.interpolate(node)

      assert result == [node]
    end

    test "string attribute" do
      node = %ElementNode{children: [], attrs: %{"key" => "value"}}
      result = Interpolator.interpolate(node)

      assert result == [node]
    end

    test "expression attribute" do
      node = %ElementNode{
        tag: "div",
        children: [],
        attrs: %{"key" => "{{ 1 }}"}
      }

      result = Interpolator.interpolate(node)

      expected =
        [
          %ElementNode{
            attrs: %{
              "key" => %Expression{
                ir: %IntegerType{value: 1}
              }
            },
            children: [],
            tag: "div"
          }
        ]
      assert result == expected
    end

    test "has children" do
      node = %ElementNode{
        children: [
          %TextNode{content: "abc"},
          %TextNode{content: "xyz"}
        ],
        attrs: %{}
      }

      result = Interpolator.interpolate(node)

      assert result == [node]
    end
  end

  test "nodes tree" do
    nodes =
      [
        %TextNode{content: "abc{{ 1 }}cde"},
        %ElementNode{
          tag: "div",
          attrs: %{"m" => "{{ 2 }}"},
          children: [
            %TextNode{content: "xyz"},
            %ElementNode{
              tag: "div",
              children: [
                %ElementNode{tag: "span", children: [], attrs: %{}}
              ],
              attrs: %{"n" => "{{ 3 }}"}
            },
            %TextNode{content: "def{{ 4 }}fgh"}
          ]
        },
        %TextNode{content: "ghi"}
      ]

    result = Interpolator.interpolate(nodes)

    expected =
      [
        %TextNode{content: "abc"},
        %Expression{ir: %IntegerType{value: 1}},
        %TextNode{content: "cde"},
        %ElementNode{
          tag: "div",
          attrs: %{"m" => %Expression{ir: %IntegerType{value: 2}}},
          children: [
            %TextNode{content: "xyz"},
            %ElementNode{
              tag: "div",
              children: [
                %ElementNode{tag: "span", children: [], attrs: %{}}
              ],
              attrs: %{"n" => %Expression{ir: %IntegerType{value: 3}}}
            },
            %TextNode{content: "def"},
            %Expression{ir: %IntegerType{value: 4}},
            %TextNode{content: "fgh"}
          ]
        },
        %TextNode{content: "ghi"}
      ]

    assert result == expected
  end
end
