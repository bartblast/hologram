defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Renderer

  alias Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module1
  alias Hologram.Test.Fixtures.Template.Renderer.Module10
  alias Hologram.Test.Fixtures.Template.Renderer.Module13
  alias Hologram.Test.Fixtures.Template.Renderer.Module14
  alias Hologram.Test.Fixtures.Template.Renderer.Module16
  alias Hologram.Test.Fixtures.Template.Renderer.Module17
  alias Hologram.Test.Fixtures.Template.Renderer.Module18
  alias Hologram.Test.Fixtures.Template.Renderer.Module19
  alias Hologram.Test.Fixtures.Template.Renderer.Module2
  alias Hologram.Test.Fixtures.Template.Renderer.Module21
  alias Hologram.Test.Fixtures.Template.Renderer.Module24
  alias Hologram.Test.Fixtures.Template.Renderer.Module25
  alias Hologram.Test.Fixtures.Template.Renderer.Module27
  alias Hologram.Test.Fixtures.Template.Renderer.Module28
  alias Hologram.Test.Fixtures.Template.Renderer.Module29
  alias Hologram.Test.Fixtures.Template.Renderer.Module3
  alias Hologram.Test.Fixtures.Template.Renderer.Module31
  alias Hologram.Test.Fixtures.Template.Renderer.Module34
  alias Hologram.Test.Fixtures.Template.Renderer.Module4
  alias Hologram.Test.Fixtures.Template.Renderer.Module5
  alias Hologram.Test.Fixtures.Template.Renderer.Module6
  alias Hologram.Test.Fixtures.Template.Renderer.Module7
  alias Hologram.Test.Fixtures.Template.Renderer.Module8
  alias Hologram.Test.Fixtures.Template.Renderer.Module9

  test "multiple nodes" do
    nodes = [
      {:text, "abc"},
      {:component, Module3, [{"id", [text: "component_3"]}], []},
      {:text, "xyz"},
      {:component, Module7, [{"id", [text: "component_7"]}], []}
    ]

    assert render(nodes, []) ==
             {"abc<div>state_a = 1, state_b = 2</div>xyz<div>state_c = 3, state_d = 4</div>",
              %{
                "component_3" => %Component.Client{state: %{a: 1, b: 2}},
                "component_7" => %Component.Client{state: %{c: 3, d: 4}}
              }}
  end

  describe "stateful component" do
    test "without props or state" do
      node = {:component, Module1, [{"id", [text: "my_component"]}], []}

      assert render(node, []) ==
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

      assert render(node, []) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>",
                %{"my_component" => %Component.Client{state: %{}}}}
    end

    test "with state / only client struct returned from init/3" do
      node = {:component, Module3, [{"id", [text: "my_component"]}], []}

      assert render(node, []) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %Component.Client{state: %{a: 1, b: 2}}}}
    end

    test "with props and state, give state priority over prop if there are name conflicts" do
      node =
        {:component, Module4,
         [
           {"id", [text: "my_component"]},
           {"b", [text: "prop_b"]},
           {"c", [text: "prop_c"]}
         ], []}

      assert render(node, []) ==
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

      assert render(node, []) ==
               {"<div>prop_a = aaa, prop_b = bbb</div>",
                %{"my_component" => %Component.Client{state: %{}}}}
    end

    test "with client and server structs returned from init/3" do
      node = {:component, Module6, [{"id", [text: "my_component"]}], []}

      assert render(node, []) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %Component.Client{state: %{a: 1, b: 2}}}}
    end

    test "with missing 'id' property" do
      node = {:component, Module13, [], []}

      assert_raise Hologram.Template.SyntaxError,
                   "Stateful component Elixir.Hologram.Test.Fixtures.Template.Renderer.Module13 is missing the 'id' property.",
                   fn ->
                     render(node, [])
                   end
    end

    test "cast props" do
      node =
        {:component, Module16,
         [
           {"id", [text: "my_component"]},
           {"prop_1", [text: "value_1"]},
           {"prop_2", [expression: {2}]},
           {"prop_3", [text: "aaa", expression: {2}, text: "bbb"]},
           {"prop_4", [text: "value_4"]}
         ], []}

      assert render(node, []) ==
               {"",
                %{
                  "my_component" => %Component.Client{
                    state: %{
                      id: "my_component",
                      prop_1: "value_1",
                      prop_2: 2,
                      prop_3: "aaa2bbb"
                    }
                  }
                }}
    end

    test "with unregistered var used" do
      node =
        {:component, Module18,
         [{"id", [text: "component_18"]}, {"a", [text: "111"]}, {"c", [text: "333"]}], []}

      assert_raise KeyError,
                   ~s(key :c not found in: %{id: "component_18", a: "111", b: 222}),
                   fn ->
                     render(node, [])
                   end
    end
  end

  describe "stateless component" do
    test "without props" do
      node = {:component, Module1, [], []}
      assert render(node, []) == {"<div>abc</div>", %{}}
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

      assert render(node, []) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>", %{}}
    end

    test "with unregistered var used" do
      node = {:component, Module17, [{"a", [text: "111"]}, {"b", [text: "222"]}], []}

      assert_raise KeyError, "key :b not found in: %{a: \"111\"}", fn ->
        render(node, [])
      end
    end
  end

  describe "element" do
    test "non-void element, without attributes or children" do
      node = {:element, "div", [], []}
      assert render(node, []) == {"<div></div>", %{}}
    end

    test "non-void element, with attributes" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render(node, []) ==
               {~s(<div attr_1="aaa" attr_2="123" attr_3="ccc987eee"></div>), %{}}
    end

    test "non-void element, with children" do
      node = {:element, "div", [], [{:element, "span", [], [text: "abc"]}, {:text, "xyz"}]}

      assert render(node, []) == {"<div><span>abc</span>xyz</div>", %{}}
    end

    test "void element, without attributes" do
      node = {:element, "img", [], []}
      assert render(node, []) == {"<img />", %{}}
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

      assert render(node, []) == {~s(<img attr_1="aaa" attr_2="123" attr_3="ccc987eee" />), %{}}
    end

    test "with nested stateful components" do
      node =
        {:element, "div", [{"attr", [text: "value"]}],
         [
           {:component, Module3, [{"id", [text: "component_3"]}], []},
           {:component, Module7, [{"id", [text: "component_7"]}], []}
         ]}

      assert render(node, []) ==
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
    assert render(node, []) == {"123", %{}}
  end

  describe "page" do
    test "render page inside layout slot" do
      node = {:page, Module14, [], []}

      assert render(node, []) ==
               {"layout template start, page template, layout template end",
                %{
                  "layout" => %Component.Client{},
                  "page" => %Component.Client{}
                }}
    end

    test "cast page params" do
      node =
        {:page, Module19,
         [
           {"param_1", [text: "value_1"]},
           {"param_2", [text: "value_2"]},
           {"param_3", [text: "value_3"]}
         ], []}

      assert render(node, []) ==
               {"",
                %{
                  "layout" => %Component.Client{},
                  "page" => %Component.Client{state: %{param_1: "value_1", param_3: "value_3"}}
                }}
    end

    test "cast layout explicit static props" do
      node = {:page, Module25, [], []}

      assert render(node, []) ==
               {"",
                %{
                  "layout" => %Component.Client{
                    state: %{id: "layout", prop_1: "prop_value_1", prop_3: "prop_value_3"}
                  },
                  "page" => %Component.Client{}
                }}
    end

    test "cast layout props passed implicitely from page state" do
      node = {:page, Module27, [], []}

      assert render(node, []) ==
               {"",
                %{
                  "layout" => %Component.Client{
                    state: %{id: "layout", prop_1: "prop_value_1", prop_3: "prop_value_3"}
                  },
                  "page" => %Component.Client{
                    state: %{
                      prop_1: "prop_value_1",
                      prop_2: "prop_value_2",
                      prop_3: "prop_value_3"
                    }
                  }
                }}
    end

    test "aggregate page vars, giving state priority over param when there are name conflicts" do
      node =
        {:page, Module21,
         [
           {"key_1", [text: "param_value_1"]},
           {"key_2", [text: "param_value_2"]}
         ], []}

      assert render(node, []) ==
               {"key_1 = param_value_1, key_2 = state_value_2, key_3 = state_value_3",
                %{
                  "layout" => %Component.Client{},
                  "page" => %Component.Client{
                    state: %{key_2: "state_value_2", key_3: "state_value_3"}
                  }
                }}
    end

    test "aggregate layout vars, giving state priority over prop when there are name conflicts" do
      node = {:page, Module24, [], []}

      assert render(node, []) ==
               {"key_1 = prop_value_1, key_2 = state_value_2, key_3 = state_value_3",
                %{
                  "layout" => %Component.Client{
                    state: %{key_2: "state_value_2", key_3: "state_value_3"}
                  },
                  "page" => %Component.Client{}
                }}
    end

    test "merge the page component client struct into the result" do
      node = {:page, Module28, [], []}

      assert render(node, []) ==
               {"",
                %{
                  "layout" => %Component.Client{},
                  "page" => %Component.Client{
                    state: %{state_1: "value_1", state_2: "value_2"}
                  }
                }}
    end

    test "merge the layout component client struct into the result" do
      node = {:page, Module29, [], []}

      assert render(node, []) ==
               {"",
                %{
                  "layout" => %Hologram.Component.Client{
                    state: %{state_1: "value_1", state_2: "value_2"}
                  },
                  "page" => %Hologram.Component.Client{}
                }}
    end
  end

  test "text" do
    node = {:text, "abc"}
    assert render(node, []) == {"abc", %{}}
  end

  describe "default slot" do
    test "with single node" do
      node = {:component, Module8, [], [text: "123"]}
      assert render(node, []) == {"abc123xyz", %{}}
    end

    test "with multiple nodes" do
      node = {:component, Module8, [], [text: "123", expression: {456}]}
      assert render(node, []) == {"abc123456xyz", %{}}
    end

    test "nested components with slots, no slot tag in the top component template, not using vars" do
      node = {:component, Module8, [], [{:component, Module9, [], [text: "789"]}]}
      assert render(node, []) == {"abcdef789uvwxyz", %{}}
    end

    test "nested components with slots, no slot tag in the top component template, using vars" do
      node = {:component, Module10, [{"id", [text: "component_10"]}], []}

      assert render(node, []) ==
               {"10,11,10,12,10",
                %{
                  "component_10" => %Component.Client{state: %{a: 10}},
                  "component_11" => %Component.Client{state: %{a: 11}},
                  "component_12" => %Component.Client{state: %{a: 12}}
                }}
    end

    test "nested components with slots, slot tag in the top component template, not using vars" do
      node = {:component, Module31, [], [text: "abc"]}

      assert render(node, []) == {"31a,32a,31b,33a,31c,abc,31x,33z,31y,32z,31z", %{}}
    end

    test "nested components with slots, slot tag in the top component template, using vars" do
      node =
        {:component, Module34, [{"id", [text: "component_34"]}, {"a", [text: "34a_prop"]}],
         [text: "abc"]}

      assert render(node, []) ==
               {"34a_prop,35a_prop,34b_state,36a_prop,34c_state,abc,34x_state,36z_state,34y_state,35z_state,34z_state",
                %{
                  "component_34" => %Component.Client{
                    state: %{
                      id: "component_34",
                      c: "34c_state",
                      a: "34a_prop",
                      y: "34y_state",
                      x: "34x_state",
                      z: "34z_state",
                      b: "34b_state"
                    }
                  },
                  "component_35" => %Component.Client{
                    state: %{id: "component_35", a: "35a_prop", z: "35z_state"}
                  },
                  "component_36" => %Component.Client{
                    state: %{id: "component_36", a: "36a_prop", z: "36z_state"}
                  }
                }}
    end
  end
end
