defmodule Hologram.Template.Renderer.ComponentTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Compiler.Reflection
  alias Hologram.Conn
  alias Hologram.Runtime
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module1
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module2
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module3
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module4
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module5

  @bindings %{test_outer_binding: 123}
  @conn %Conn{}

  setup do
    [app_path: "#{@fixtures_path}/template/renderers/component_renderer"]
    |> compile()

    Runtime.run()

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
          test_prop: [
            %TextNode{content: "test_prop_value"},
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"1.test_prop_value", %{test_state: 1}}

      assert result == expected
    end

    test "initial state has precendence over props in bindings" do
      component = %Component{
        module: Module2,
        props: %{
          test_state: [
            %TextNode{content: "try_to_override_test_state"}
          ],
          test_prop: [
            %TextNode{content: "test_prop_value"},
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"1.test_prop_value", %{test_state: 1}}

      assert result == expected
    end
  end

  describe "state initialization" do
    test "init/1" do
      component = %Component{
        module: Module3,
        props: %{
          test_prop: [
            %TextNode{content: "test_prop_value"},
          ]
        }
      }

      result = Renderer.render(component, @conn, @bindings)
      expected = {"abc.test_prop_value.xyz", %{test_state: "test_prop_value"}}

      assert result == expected
    end

    test "init/2" do
      component = %Component{
        module: Module4,
        props: %{
          test_prop: [
            %TextNode{content: "test_prop_value"},
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
        %{test_state_1: "test_prop_value", test_state_2: "test_session_value"}
      }

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
        %TextNode{content: ".xyz"},
      ]
    }

    result = Renderer.render(component, @conn, @bindings)
    expected = {"<span>abc.133.xyz</span>", %{}}

    assert result == expected
  end
end
