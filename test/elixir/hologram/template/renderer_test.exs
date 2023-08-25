defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Renderer

  alias Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module1
  alias Hologram.Test.Fixtures.Template.Renderer.Module2
  alias Hologram.Test.Fixtures.Template.Renderer.Module3
  alias Hologram.Test.Fixtures.Template.Renderer.Module4
  alias Hologram.Test.Fixtures.Template.Renderer.Module5
  alias Hologram.Test.Fixtures.Template.Renderer.Module6
  alias Hologram.Test.Fixtures.Template.Renderer.Module7

  test "multiple nodes" do
    nodes = [
      {:text, "abc"},
      {:component, Module3, [{"id", [text: "component_3"]}], []},
      {:text, "xyz"},
      {:component, Module7, [{"id", [text: "component_7"]}], []}
    ]

    assert render(nodes) ==
             {"abc<div>state_a = 1, state_b = 2</div>xyz<div>state_c = 3, state_d = 4</div>",
              %{
                "component_3" => %Component.Client{state: %{a: 1, b: 2}},
                "component_7" => %Component.Client{state: %{c: 3, d: 4}}
              }}
  end

  describe "stateful component" do
    test "without props or state" do
      node = {:component, Module1, [{"id", [text: "my_component"]}], []}

      assert render(node) ==
               {"<div>abc</div>", %{"my_component" => %Component.Client{state: %{}}}}
    end

    test "with props" do
      node = [
        {:component, Module2,
         [
           {"id", [text: "my_component"]},
           {"a", [text: "ddd"]},
           {"b", [expression: {222}]},
           {"c", [text: "fff", expression: {333}, text: "hhh"]}
         ], []}
      ]

      assert render(node) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>",
                %{"my_component" => %Component.Client{state: %{}}}}
    end

    test "with state / only client struct returned from init/3" do
      node = {:component, Module3, [{"id", [text: "my_component"]}], []}

      assert render(node) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %Component.Client{state: %{a: 1, b: 2}}}}
    end

    test "with props and state" do
      node =
        {:component, Module4,
         [
           {"id", [text: "my_component"]},
           {"b", [text: "prop_b"]},
           {"c", [text: "prop_c"]}
         ], []}

      assert render(node) ==
               {"<div>var_a = state_a, var_b = state_b, var_c = prop_c</div>",
                %{"my_component" => %Component.Client{state: %{a: "state_a", b: "state_b"}}}}
    end

    test "with only server struct returned from init/3" do
      node = [
        {:component, Module5,
         [
           {"id", [text: "my_component"]},
           {"a", [text: "aaa"]},
           {"b", [text: "bbb"]}
         ], []}
      ]

      assert render(node) ==
               {"<div>prop_a = aaa, prop_b = bbb</div>",
                %{"my_component" => %Component.Client{state: %{}}}}
    end

    test "with client and server structs returned from init/3" do
      node = {:component, Module6, [{"id", [text: "my_component"]}], []}

      assert render(node) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %Component.Client{state: %{a: 1, b: 2}}}}
    end
  end

  describe "stateless component" do
    test "without props" do
      node = {:component, Module1, [], []}
      assert render(node) == {"<div>abc</div>", %{}}
    end

    test "with props" do
      node = [
        {:component, Module2,
         [
           {"a", [text: "ddd"]},
           {"b", [expression: {222}]},
           {"c", [text: "fff", expression: {333}, text: "hhh"]}
         ], []}
      ]

      assert render(node) == {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>", %{}}
    end
  end

  describe "element" do
    test "non-void element, without attributes or children" do
      node = {:element, "div", [], []}
      assert render(node) == {"<div></div>", %{}}
    end

    test "non-void element, with attributes" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render(node) == {~s(<div attr_1="aaa" attr_2="123" attr_3="ccc987eee"></div>), %{}}
    end

    test "non-void element, with children" do
      node = {:element, "div", [], [{:element, "span", [], [text: "abc"]}, {:text, "xyz"}]}

      assert render(node) == {"<div><span>abc</span>xyz</div>", %{}}
    end

    test "void element, without attributes" do
      node = {:element, "img", [], []}
      assert render(node) == {"<img />", %{}}
    end

    test "void element, with attributes" do
      node = [
        {:element, "img",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}
      ]

      assert render(node) == {~s(<img attr_1="aaa" attr_2="123" attr_3="ccc987eee" />), %{}}
    end

    test "with nested stateful components" do
      node =
        {:element, "div", [{"attr", [text: "value"]}],
         [
           {:component, Module3, [{"id", [text: "component_3"]}], []},
           {:component, Module7, [{"id", [text: "component_7"]}], []}
         ]}

      assert render(node) ==
               {~s(<div attr="value"><div>state_a = 1, state_b = 2</div><div>state_c = 3, state_d = 4</div></div>),
                %{
                  "component_3" => %Component.Client{
                    state: %{a: 1, b: 2}
                  },
                  "component_7" => %Component.Client{
                    state: %{c: 3, d: 4}
                  }
                }}
    end
  end

  test "expression" do
    node = {:expression, {123}}
    assert render(node) == {"123", %{}}
  end

  test "text" do
    node = {:text, "abc"}
    assert render(node) == {"abc", %{}}
  end
end
