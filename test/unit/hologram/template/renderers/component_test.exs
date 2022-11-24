defmodule Hologram.Template.Renderer.ComponentTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Conn
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module1
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module2
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module3
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module4
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module5
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module6
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module8

  @bindings %{__context__: %{}, test_outer_binding: 123}
  @conn %Conn{}

  setup do
    [app_path: "#{@fixtures_path}/template/renderers/component_renderer"]
    |> compile()

    run_runtime()

    :ok
  end

  describe "props" do
    test "text prop" do
      component = %Component{
        module: Module1,
        props: %{
          test_prop: [%TextNode{content: "test_prop_value"}]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"abc.test_prop_value.xyz", %{}}

      assert result == expected
    end

    test "expression prop" do
      component = %Component{
        module: Module1,
        props: %{
          test_prop: [
            %Expression{
              ir: %TupleType{
                data: [
                  %AdditionOperator{
                    left: %IntegerType{value: 10},
                    right: %ModuleAttributeOperator{name: :test_outer_binding}
                  }
                ]
              }
            }
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"abc.133.xyz", %{}}

      assert result == expected
    end

    test "multiple parts prop" do
      component = %Component{
        module: Module1,
        props: %{
          test_prop: [
            %TextNode{content: "test_prop_value"},
            %Expression{
              ir: %TupleType{
                data: [
                  %AdditionOperator{
                    left: %IntegerType{value: 10},
                    right: %ModuleAttributeOperator{name: :test_outer_binding}
                  }
                ]
              }
            }
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"abc.test_prop_value133.xyz", %{}}

      assert result == expected
    end
  end

  describe "bindings" do
    test "bindings are combined from props and initial state" do
      component = %Component{
        module: Module2,
        props: %{
          id: [
            %TextNode{content: "component_2"}
          ],
          test_prop: [
            %TextNode{content: "test_prop_value"}
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"1.test_prop_value", %{component_2: %{test_state: 1}}}

      assert result == expected
    end

    test "initial state has precendence over props in bindings" do
      component = %Component{
        module: Module2,
        props: %{
          id: [
            %TextNode{content: "component_2"}
          ],
          test_state: [
            %TextNode{content: "try_to_override_test_state"}
          ],
          test_prop: [
            %TextNode{content: "test_prop_value"}
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"1.test_prop_value", %{component_2: %{test_state: 1}}}

      assert result == expected
    end
  end

  describe "state initialization" do
    test "init/1" do
      component = %Component{
        module: Module3,
        props: %{
          id: [
            %TextNode{content: "component_3"}
          ],
          test_prop: [
            %TextNode{content: "test_prop_value"}
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"abc.test_prop_value.xyz", %{component_3: %{test_state: "test_prop_value"}}}

      assert result == expected
    end

    test "init/2" do
      component = %Component{
        module: Module4,
        props: %{
          id: [
            %TextNode{content: "component_3"}
          ],
          test_prop: [
            %TextNode{content: "test_prop_value"}
          ]
        }
      }

      conn = %Conn{
        session: %{
          test_session_key: "test_session_value"
        }
      }

      result = Renderer.render(component, conn, @bindings)

      expected = {
        "test_prop_value.test_session_value",
        %{
          component_3: %{
            test_state_1: "test_prop_value",
            test_state_2: "test_session_value"
          }
        }
      }

      assert result == expected
    end

    test "nested state" do
      component = %Component{
        module: Module6,
        props: %{
          id: [
            %TextNode{content: "parent_component"}
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)

      expected_html = "parent_head.child.parent_tail"

      expected_state = %{
        child_component: %{child_component_state_key: "child_component_state_value"},
        parent_component: %{parent_component_state_key: "parent_component_state_value"}
      }

      expected = {expected_html, expected_state}

      assert result == expected
    end
  end

  test "default slot" do
    component = %Component{
      module: Module5,
      children: [
        %TextNode{content: "abc."},
        %Expression{
          ir: %TupleType{
            data: [
              %AdditionOperator{
                left: %IntegerType{value: 10},
                right: %ModuleAttributeOperator{name: :test_outer_binding}
              }
            ]
          }
        },
        %TextNode{content: ".xyz"}
      ]
    }

    result = Renderer.render(component, @conn, @bindings)
    expected = {"<span>abc.133.xyz</span>", %{}}

    assert result == expected
  end

  test "context passing" do
    component = %Component{
      module: Module8,
      props: %{
        id: [
          %TextNode{content: "component_8_id"}
        ]
      }
    }

    context = %{test_context_key: "test_context_value"}
    bindings = Map.put(@bindings, :__context__, context)

    result = Renderer.render(component, @conn, bindings)

    expected_initial_state = %{
      component_8_id: %{component_8_state_key: "component_8_state_value"},
      component_9_id: %{component_9_state_key: "component_9_state_value"}
    }

    expected_html = "abc(in component 9: test_context_value)xyz"
    expected = {expected_html, expected_initial_state}

    assert result == expected
  end
end
