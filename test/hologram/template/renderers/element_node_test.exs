defmodule Hologram.Template.Renderer.ElementNodeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeOperator, NilType, TupleType}
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.{ElementNode, Expression, TextNode}

  @attrs %{
    attr_2: %{
      value: [
        %TextNode{content: "test_text_2"}
      ],
      modifiers: []
    },
    attr_1: %{
      value: [
        %Expression{
          ir: %TupleType{
            data: [
              %ModuleAttributeOperator{name: :a}
            ]
          }
        }
      ],
      modifiers: []
    }
  }

  @bindings %{a: 123}

  @children [
    %TextNode{content: "abc"},
    %Expression{
      ir: %TupleType{
        data: [
          %ModuleAttributeOperator{name: :a}
        ]
      }
    },
    %TextNode{content: "xyz"}
  ]

  test "non-void element without attributes or children" do
    element_node = %ElementNode{attrs: %{}, children: [], tag: "div"}
    result = Renderer.render(element_node, @bindings)

    assert result == "<div></div>"
  end

  test "non-void element with attributes" do
    element_node = %ElementNode{attrs: @attrs, children: [], tag: "div"}

    result = Renderer.render(element_node, @bindings)
    expected = "<div attr_1=\"123\" attr_2=\"test_text_2\"></div>"

    assert result == expected
  end

  test "non-void element with children" do
    element_node = %ElementNode{attrs: %{}, children: @children, tag: "div"}

    result = Renderer.render(element_node, @bindings)
    expected = "<div>abc123xyz</div>"

    assert result == expected
  end

  test "non-void element with children and attributes" do
    element_node = %ElementNode{attrs: @attrs, children: @children, tag: "div"}

    result = Renderer.render(element_node, @bindings)
    expected = "<div attr_1=\"123\" attr_2=\"test_text_2\">abc123xyz</div>"

    assert result == expected
  end

  test "void element without attributes" do
    element_node = %ElementNode{attrs: %{}, children: [], tag: "input"}
    result = Renderer.render(element_node, @bindings)

    assert result == "<input />"
  end

  test "void element with attributes" do
    element_node = %ElementNode{attrs: @attrs, children: [], tag: "input"}

    result = Renderer.render(element_node, @bindings)
    expected = "<input attr_1=\"123\" attr_2=\"test_text_2\" />"

    assert result == expected
  end

  test "slot tag" do
    element_node = %ElementNode{attrs: %{}, children: @children, tag: "slot"}

    result = Renderer.render(element_node, @bindings, default: @children)
    expected = "abc123xyz"

    assert result == expected
  end

  test "pruned attrs" do
    attrs = %{
      non_pruned_attr: %{
        value: [
          %TextNode{content: "test_non_pruned_attr_content"}
        ],
        modifiers: []
      },
      on_click: %{
        value: [
          %TextNode{content: "test_pruned_attr_content"}
        ],
        modifiers: []
      }
    }

    element_node = %ElementNode{attrs: attrs, children: [], tag: "input"}

    result = Renderer.render(element_node, @bindings)
    expected = "<input non_pruned_attr=\"test_non_pruned_attr_content\" />"

    assert result == expected
  end

  test "if attribute which evaluates to a truthy value" do
    attrs = %{
      if: %{
        value: [
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 123}]
            }
          }
        ],
        modifiers: []
      }
    }

    element_node = %ElementNode{attrs: attrs, children: [], tag: "div"}
    result = Renderer.render(element_node, @bindings)

    assert result == "<div></div>"
  end

  test "if attribute which evaluates to a falsy value" do
    attrs = %{
      if: %{
        value: [
          %Expression{
            ir: %TupleType{
              data: [%NilType{}]
            }
          }
        ],
        modifiers: []
      }
    }

    element_node = %ElementNode{attrs: attrs, children: [], tag: "div"}
    result = Renderer.render(element_node, @bindings)

    assert result == ""
  end
end
