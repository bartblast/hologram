defmodule Hologram.Template.Renderer.NodeListTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Conn
  alias Hologram.Runtime
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.VDOM.TextNode
  alias Hologram.Test.Fixtures.Template.NodeListRenderer.Module1
  alias Hologram.Test.Fixtures.Template.NodeListRenderer.Module2

  setup do
    [app_path: "#{@fixtures_path}/template/renderers/node_list_renderer"]
    |> compile()

    Runtime.run()

    :ok
  end

  test "render/4" do
    component_1 = %Component{
      module: Module1,
      props: %{
        id: [
          %TextNode{content: "component_1_id"},
        ]
      }
    }

    component_2 = %Component{
      module: Module2,
      props: %{
        id: [
          %TextNode{content: "component_2_id"},
        ]
      }
    }

    nodes = [
      %TextNode{content: "test_1"},
      component_1,
      %TextNode{content: "test_2"},
      component_2
    ]

    bindings = %{__context__: %{}}
    result = Renderer.render(nodes, %Conn{}, bindings)

    expected_initial_state = %{
      component_1_id: %{component_1_state_key: "component_1_state_value"},
      component_2_id: %{component_2_state_key: "component_2_state_value"},
    }

    expected_html = "test_1(in component 1)test_2(in component 2)"
    expected = {expected_html, expected_initial_state}

    assert result == expected
  end
end
