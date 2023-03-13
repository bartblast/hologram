defmodule Hologram.Template.Renderer.ElementNodeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.BooleanType
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.NilType
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode
  alias Hologram.Test.Fixtures.Template.ElementNodeRenderer.Module1
  alias Hologram.Test.Fixtures.Template.ElementNodeRenderer.Module2

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

  @bindings %{
    __context__: %{},
    a: 123
  }

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

  @conn %Hologram.Conn{}

  test "non-void element without attributes or children" do
    element_node = %ElementNode{attrs: %{}, children: [], tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div></div>", %{}}

    assert result == expected
  end

  test "non-void element with attributes" do
    element_node = %ElementNode{attrs: @attrs, children: [], tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div attr_1=\"123\" attr_2=\"test_text_2\"></div>", %{}}

    assert result == expected
  end

  test "non-void element with children" do
    element_node = %ElementNode{attrs: %{}, children: @children, tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div>abc123xyz</div>", %{}}

    assert result == expected
  end

  test "non-void element with children and attributes" do
    element_node = %ElementNode{attrs: @attrs, children: @children, tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div attr_1=\"123\" attr_2=\"test_text_2\">abc123xyz</div>", %{}}

    assert result == expected
  end

  test "void element without attributes" do
    element_node = %ElementNode{attrs: %{}, children: [], tag: "input"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<input />", %{}}

    assert result == expected
  end

  test "void element with attributes" do
    element_node = %ElementNode{attrs: @attrs, children: [], tag: "input"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<input attr_1=\"123\" attr_2=\"test_text_2\" />", %{}}

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
      "on:click": %{
        value: [
          %TextNode{content: "test_pruned_attr_content"}
        ],
        modifiers: []
      }
    }

    element_node = %ElementNode{attrs: attrs, children: [], tag: "input"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<input non_pruned_attr=\"test_non_pruned_attr_content\" />", %{}}

    assert result == expected
  end

  test "'if' attribute which evaluates to a truthy value" do
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

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div></div>", %{}}

    assert result == expected
  end

  test "'if' attribute which evaluates to a falsy value" do
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

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"", %{}}

    assert result == expected
  end

  test "boolean attribute" do
    attrs = %{
      test_attr: %{
        value: nil,
        modifiers: []
      }
    }

    element_node = %ElementNode{attrs: attrs, children: [], tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div test_attr></div>", %{}}

    assert result == expected
  end

  test "expression attribute which evaluates to false" do
    attrs = %{
      test_attr: %{
        value: [
          %Expression{
            ir: %TupleType{
              data: [%BooleanType{value: false}]
            }
          }
        ],
        modifiers: []
      }
    }

    element_node = %ElementNode{attrs: attrs, children: [], tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div></div>", %{}}

    assert result == expected
  end

  test "expression attribute which evaluates to nil" do
    attrs = %{
      test_attr: %{
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

    result = Renderer.render(element_node, @conn, @bindings)
    expected = {"<div test_attr></div>", %{}}

    assert result == expected
  end

  test "default slot" do
    element_node = %ElementNode{attrs: %{}, children: @children, tag: "slot"}

    slot_bindings = %{a: 987}
    slots = {slot_bindings, default: @children}

    result = Renderer.render(element_node, @conn, @bindings, slots)
    expected = {"abc987xyz", %{}}

    assert result == expected
  end

  test "nested components state" do
    [app_path: "#{@fixtures_path}/template/renderers/element_node_renderer"]
    |> compile()

    run_runtime()

    component_1 = %Component{
      module: Module1,
      props: %{
        id: [
          %TextNode{content: "component_1_id"}
        ]
      }
    }

    component_2 = %Component{
      module: Module2,
      props: %{
        id: [
          %TextNode{content: "component_2_id"}
        ]
      }
    }

    children = [
      %TextNode{content: "abc"},
      component_1,
      %TextNode{content: "xyz"},
      component_2
    ]

    element_node = %ElementNode{attrs: %{}, children: children, tag: "div"}

    result = Renderer.render(element_node, @conn, @bindings)

    expected_initial_state = %{
      component_1_id: %{component_1_state_key: "component_1_state_value"},
      component_2_id: %{component_2_state_key: "component_2_state_value"}
    }

    expected_html = "<div>abc(in component 1)xyz(in component 2)</div>"
    expected = {expected_html, expected_initial_state}

    assert result == expected
  end
end
