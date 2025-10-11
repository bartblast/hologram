defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Component
  alias Hologram.Runtime.Cookie
  alias Hologram.Server
  alias Hologram.Server.Metadata
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.LayoutFixture
  alias Hologram.Test.Fixtures.Template.Renderer.Module1
  alias Hologram.Test.Fixtures.Template.Renderer.Module10
  alias Hologram.Test.Fixtures.Template.Renderer.Module11
  alias Hologram.Test.Fixtures.Template.Renderer.Module12
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
  alias Hologram.Test.Fixtures.Template.Renderer.Module30
  alias Hologram.Test.Fixtures.Template.Renderer.Module31
  alias Hologram.Test.Fixtures.Template.Renderer.Module34
  alias Hologram.Test.Fixtures.Template.Renderer.Module35
  alias Hologram.Test.Fixtures.Template.Renderer.Module36
  alias Hologram.Test.Fixtures.Template.Renderer.Module37
  alias Hologram.Test.Fixtures.Template.Renderer.Module39
  alias Hologram.Test.Fixtures.Template.Renderer.Module4
  alias Hologram.Test.Fixtures.Template.Renderer.Module40
  alias Hologram.Test.Fixtures.Template.Renderer.Module41
  alias Hologram.Test.Fixtures.Template.Renderer.Module42
  alias Hologram.Test.Fixtures.Template.Renderer.Module43
  alias Hologram.Test.Fixtures.Template.Renderer.Module44
  alias Hologram.Test.Fixtures.Template.Renderer.Module45
  alias Hologram.Test.Fixtures.Template.Renderer.Module46
  alias Hologram.Test.Fixtures.Template.Renderer.Module47
  alias Hologram.Test.Fixtures.Template.Renderer.Module48
  alias Hologram.Test.Fixtures.Template.Renderer.Module5
  alias Hologram.Test.Fixtures.Template.Renderer.Module50
  alias Hologram.Test.Fixtures.Template.Renderer.Module51
  alias Hologram.Test.Fixtures.Template.Renderer.Module52
  alias Hologram.Test.Fixtures.Template.Renderer.Module53
  alias Hologram.Test.Fixtures.Template.Renderer.Module6
  alias Hologram.Test.Fixtures.Template.Renderer.Module62
  alias Hologram.Test.Fixtures.Template.Renderer.Module64
  alias Hologram.Test.Fixtures.Template.Renderer.Module65
  alias Hologram.Test.Fixtures.Template.Renderer.Module66
  alias Hologram.Test.Fixtures.Template.Renderer.Module67
  alias Hologram.Test.Fixtures.Template.Renderer.Module69
  alias Hologram.Test.Fixtures.Template.Renderer.Module7
  alias Hologram.Test.Fixtures.Template.Renderer.Module70
  alias Hologram.Test.Fixtures.Template.Renderer.Module76
  alias Hologram.Test.Fixtures.Template.Renderer.Module77
  alias Hologram.Test.Fixtures.Template.Renderer.Module8
  alias Hologram.Test.Fixtures.Template.Renderer.Module9

  @csrf_token "test-csrf-token"
  @env %Renderer.Env{}
  @opts [csrf_token: @csrf_token, initial_page?: true]
  @params %{}

  @server %Server{
    cookies: %{
      "initial_cookie_key" => :initial_cookie_value
    },
    __meta__: %Metadata{
      cookie_ops: %{
        "initial_cookie_key" => %Cookie{value: :initial_cookie_value}
      }
    }
  }

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  test "text node" do
    node = {:text, "Hologram"}
    assert render_dom(node, @env, @server) == {"Hologram", %{}, @server}
  end

  describe "public comment node" do
    test "empty" do
      # <!---->
      node = {:public_comment, []}

      assert render_dom(node, @env, @server) == {"<!---->", %{}, @server}
    end

    test "with single child" do
      # <!--<div></div>-->
      node = {:public_comment, [{:element, "div", [], []}]}

      assert render_dom(node, @env, @server) == {"<!--<div></div>-->", %{}, @server}
    end

    test "with multiple children" do
      # <!--abc<div></div>-->
      node = {:public_comment, [{:text, "abc"}, {:element, "div", [], []}]}

      assert render_dom(node, @env, @server) == {"<!--abc<div></div>-->", %{}, @server}
    end

    test "with nested stateful components" do
      # <!--<div attr="value"><Module3 /><Module7 /></div>-->
      node =
        {:public_comment,
         [
           {:element, "div", [{"attr", [text: "value"]}],
            [
              {:component, Module3, [{"cid", [text: "component_3"]}], []},
              {:component, Module7, [{"cid", [text: "component_7"]}], []}
            ]}
         ]}

      assert render_dom(node, @env, @server) ==
               {~s(<!--<div attr="value"><div>state_a = 1, state_b = 2</div><div>state_c = 3, state_d = 4</div></div>-->),
                %{
                  "component_3" => %{
                    module: Module3,
                    struct: %Component{
                      state: %{a: 1, b: 2}
                    }
                  },
                  "component_7" => %{
                    module: Module7,
                    struct: %Component{
                      state: %{c: 3, d: 4}
                    }
                  }
                },
                %Server{
                  cookies: %{
                    "initial_cookie_key" => :initial_cookie_value,
                    "cookie_key_3" => :cookie_value_3,
                    "cookie_key_7" => :cookie_value_7
                  },
                  __meta__: %Metadata{
                    cookie_ops: %{
                      "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                      "cookie_key_3" => %Cookie{value: :cookie_value_3},
                      "cookie_key_7" => %Cookie{value: :cookie_value_7}
                    }
                  }
                }}
    end
  end

  test "DOCTYPE node" do
    node = {:doctype, "html"}
    assert render_dom(node, @env, @server) == {"<!DOCTYPE html>", %{}, @server}
  end

  test "expression node" do
    # {123}
    node = {:expression, {123}}

    assert render_dom(node, @env, @server) == {"123", %{}, @server}
  end

  describe "element node" do
    test "non-void element, without attributes or children" do
      node = {:element, "div", [], []}
      assert render_dom(node, @env, @server) == {"<div></div>", %{}, @server}
    end

    test "non-void element, with attributes" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div attr_1="aaa" attr_2="123" attr_3="ccc987eee"></div>), %{}, @server}
    end

    test "non-void element, with children" do
      node = {:element, "div", [], [{:element, "span", [], [text: "abc"]}, {:text, "xyz"}]}
      assert render_dom(node, @env, @server) == {"<div><span>abc</span>xyz</div>", %{}, @server}
    end

    test "void element, without attributes" do
      node = {:element, "img", [], []}
      assert render_dom(node, @env, @server) == {"<img />", %{}, @server}
    end

    test "void element, with attributes" do
      node =
        {:element, "img",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<img attr_1="aaa" attr_2="123" attr_3="ccc987eee" />), %{}, @server}
    end

    test "boolean attributes" do
      node = {:element, "img", [{"attr_1", []}, {"attr_2", [text: ""]}], []}
      assert render_dom(node, @env, @server) == {~s(<img attr_1 attr_2 />), %{}, @server}
    end

    test "attributes that evaluate to nil are not rendered" do
      node =
        {:element, "img",
         [
           {"attr_1", [expression: {nil}]},
           {"attr_2", [expression: {"value_2"}]},
           {"attr_3", [expression: {nil}]}
         ], []}

      assert render_dom(node, @env, @server) == {~s(<img attr_2="value_2" />), %{}, @server}
    end

    test "attributes that evaluate to false are not rendered" do
      node =
        {:element, "img",
         [
           {"attr_1", [expression: {false}]},
           {"attr_2", [expression: {"value_2"}]},
           {"attr_3", [expression: {false}]}
         ], []}

      assert render_dom(node, @env, @server) == {~s(<img attr_2="value_2" />), %{}, @server}
    end

    test "if there are no attributes to render there is no whitespace inside the tag, non-void element" do
      node =
        {:element, "div",
         [
           {"attr_1", [expression: {nil}]},
           {"attr_2", [expression: {nil}]}
         ], []}

      assert render_dom(node, @env, @server) == {~s(<div></div>), %{}, @server}
    end

    test "if there are no attributes to render there is no whitespace inside the tag, void element" do
      node =
        {:element, "img",
         [
           {"attr_1", [expression: {nil}]},
           {"attr_2", [expression: {nil}]}
         ], []}

      assert render_dom(node, @env, @server) == {~s(<img />), %{}, @server}
    end

    test "filters out attributes that specify event handlers (starting with '$' character)" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "aaa"]},
           {"$attr_2", [text: "bbb"]},
           {"attr_3", [expression: {111}]},
           {"$attr_4", [expression: {222}]},
           {"attr_5", [text: "ccc", expression: {999}, text: "ddd"]},
           {"$attr_6", [text: "eee", expression: {888}, text: "fff"]},
           {"attr_7", []},
           {"$attr_8", []}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div attr_1="aaa" attr_3="111" attr_5="ccc999ddd" attr_7></div>), %{}, @server}
    end

    test "with nested stateful components" do
      node =
        {:element, "div", [{"attr", [text: "value"]}],
         [
           {:component, Module3, [{"cid", [text: "component_3"]}], []},
           {:component, Module7, [{"cid", [text: "component_7"]}], []}
         ]}

      assert render_dom(node, @env, @server) ==
               {~s(<div attr="value"><div>state_a = 1, state_b = 2</div><div>state_c = 3, state_d = 4</div></div>),
                %{
                  "component_3" => %{
                    module: Module3,
                    struct: %Component{
                      state: %{a: 1, b: 2}
                    }
                  },
                  "component_7" => %{
                    module: Module7,
                    struct: %Component{
                      state: %{c: 3, d: 4}
                    }
                  }
                },
                %Server{
                  cookies: %{
                    "initial_cookie_key" => :initial_cookie_value,
                    "cookie_key_3" => :cookie_value_3,
                    "cookie_key_7" => :cookie_value_7
                  },
                  __meta__: %Metadata{
                    cookie_ops: %{
                      "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                      "cookie_key_3" => %Cookie{value: :cookie_value_3},
                      "cookie_key_7" => %Cookie{value: :cookie_value_7}
                    }
                  }
                }}
    end
  end

  # Some client tests are different than server tests.
  describe "node list" do
    test "text and expression nodes" do
      nodes = [
        {:text, "aaa"},
        {:expression, {111}},
        {:text, "bbb"},
        {:expression, {222}}
      ]

      assert render_dom(nodes, @env, @server) == {"aaa111bbb222", %{}, @server}
    end

    test "nil nodes" do
      nodes = [
        {:text, "abc"},
        nil,
        {:text, "xyz"},
        nil
      ]

      assert render_dom(nodes, @env, @server) == {"abcxyz", %{}, @server}
    end

    test "with components having a root node" do
      nodes = [
        {:text, "abc"},
        {:component, Module3, [{"cid", [text: "component_3"]}], []},
        {:text, "xyz"},
        {:component, Module7, [{"cid", [text: "component_7"]}], []}
      ]

      assert render_dom(nodes, @env, @server) ==
               {
                 "abc<div>state_a = 1, state_b = 2</div>xyz<div>state_c = 3, state_d = 4</div>",
                 %{
                   "component_3" => %{module: Module3, struct: %Component{state: %{a: 1, b: 2}}},
                   "component_7" => %{module: Module7, struct: %Component{state: %{c: 3, d: 4}}}
                 },
                 %Server{
                   cookies: %{
                     "initial_cookie_key" => :initial_cookie_value,
                     "cookie_key_3" => :cookie_value_3,
                     "cookie_key_7" => :cookie_value_7
                   },
                   __meta__: %Metadata{
                     cookie_ops: %{
                       "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                       "cookie_key_3" => %Cookie{value: :cookie_value_3},
                       "cookie_key_7" => %Cookie{value: :cookie_value_7}
                     }
                   }
                 }
               }
    end

    test "with components not having a root node" do
      nodes = [
        {:text, "abc"},
        {:component, Module51, [{"cid", [text: "component_51"]}], []},
        {:text, "xyz"},
        {:component, Module52, [{"cid", [text: "component_52"]}], []}
      ]

      assert render_dom(nodes, @env, @server) ==
               {
                 "abc<div>state_a = 1</div><div>state_b = 2</div>xyz<div>state_c = 3</div><div>state_d = 4</div>",
                 %{
                   "component_51" => %{module: Module51, struct: %Component{state: %{a: 1, b: 2}}},
                   "component_52" => %{module: Module52, struct: %Component{state: %{c: 3, d: 4}}}
                 },
                 %Server{
                   cookies: %{
                     "initial_cookie_key" => :initial_cookie_value,
                     "cookie_key_51" => :cookie_value_51,
                     "cookie_key_52" => :cookie_value_52
                   },
                   __meta__: %Metadata{
                     cookie_ops: %{
                       "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                       "cookie_key_51" => %Cookie{value: :cookie_value_51},
                       "cookie_key_52" => %Cookie{value: :cookie_value_52}
                     }
                   }
                 }
               }
    end
  end

  describe "component props" do
    test "single-valued" do
      node = {:component, Module64, [{"my_prop", [expression: {123}]}], []}
      assert render_dom(node, @env, @server) == {"my_prop = 123", %{}, @server}
    end

    test "multi-valued" do
      node = {:component, Module64, [{"my_prop", [expression: {1, 2, 3}]}], []}
      assert render_dom(node, @env, @server) == {"my_prop = {1, 2, 3}", %{}, @server}
    end

    test "cast" do
      node =
        {:component, Module16,
         [
           {"cid", [text: "my_component"]},
           {"prop_1", [text: "value_1"]},
           {"prop_2", [expression: {2}]},
           {"prop_3", [text: "aaa", expression: {2}, text: "bbb"]},
           {"prop_4", [text: "value_4"]}
         ], []}

      assert {~s'component vars = %{cid: &quot;my_component&quot;, prop_1: &quot;value_1&quot;, prop_2: 2, prop_3: &quot;aaa2bbb&quot;}',
              _component_registry, _server_struct} = render_dom(node, @env, @server)
    end

    test "default value specified" do
      node = {:component, Module65, [{"prop_2", [expression: {:xyz}]}], []}

      assert {~s'component vars = %{prop_1: &quot;abc&quot;, prop_2: :xyz, prop_3: 123}',
              _component_registry, _server_struct} = render_dom(node, @env, @server)
    end

    test "default value not specified" do
      node = {:component, Module66, [{"prop_2", [expression: {:xyz}]}], []}

      assert {~s'component vars = %{prop_2: :xyz}', _component_registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "declared to take value from context, value in context" do
      node = {:component, Module37, [{"cid", [text: "component_37"]}], []}

      assert {"prop_aaa = 123", _component_registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "declared to take value from context, value not in context, default value not specified" do
      node = {:component, Module76, [{"cid", [text: "component_76"]}], []}

      assert_raise KeyError, build_key_error_msg(:aaa, %{}), fn ->
        render_dom(node, @env, @server)
      end
    end

    test "declared to take value from context, value not in context, default value specified" do
      node = {:component, Module77, [{"cid", [text: "component_77"]}], []}

      assert {"prop_aaa = 987", _component_registry, _server_struct} =
               render_dom(node, @env, @server)
    end
  end

  describe "stateless component" do
    test "without props" do
      node = {:component, Module1, [], []}
      assert render_dom(node, @env, @server) == {"<div>abc</div>", %{}, @server}
    end

    test "with props" do
      node =
        {:component, Module2,
         [
           {"a", [text: "ddd"]},
           {"b", [expression: {222}]},
           {"c", [text: "fff", expression: {333}, text: "hhh"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>", %{}, @server}
    end

    test "with unregistered var used" do
      node = {:component, Module17, [{"a", [text: "111"]}, {"b", [text: "222"]}], []}

      expected_msg = build_key_error_msg(:b, %{a: "111"})

      assert_raise KeyError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end
  end

  # Some client tests are different than server tests.
  describe "stateful component" do
    test "without props or state" do
      node = {:component, Module1, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env, @server) ==
               {"<div>abc</div>",
                %{"my_component" => %{module: Module1, struct: %Component{state: %{}}}}, @server}
    end

    test "with props" do
      node =
        {:component, Module2,
         [
           {"cid", [text: "my_component"]},
           {"a", [text: "ddd"]},
           {"b", [expression: {222}]},
           {"c", [text: "fff", expression: {333}, text: "hhh"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>",
                %{"my_component" => %{module: Module2, struct: %Component{state: %{}}}}, @server}
    end

    test "with state / only component struct returned from init/3" do
      node = {:component, Module69, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env, @server) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{
                  "my_component" => %{module: Module69, struct: %Component{state: %{a: 1, b: 2}}}
                }, @server}
    end

    test "with props and state, give state priority over prop if there are name collisions" do
      node =
        {:component, Module4,
         [
           {"cid", [text: "my_component"]},
           {"b", [text: "prop_b"]},
           {"c", [text: "prop_c"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {"<div>var_a = state_a, var_b = state_b, var_c = prop_c</div>",
                %{
                  "my_component" => %{
                    module: Module4,
                    struct: %Component{state: %{a: "state_a", b: "state_b"}}
                  }
                }, @server}
    end

    test "with only server struct returned from init/3" do
      node =
        {:component, Module5,
         [
           {"cid", [text: "my_component"]},
           {"a", [text: "aaa"]},
           {"b", [text: "bbb"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {
                 "<div>prop_a = aaa, prop_b = bbb</div>",
                 %{"my_component" => %{module: Module5, struct: %Component{state: %{}}}},
                 %Server{
                   cookies: %{
                     "initial_cookie_key" => :initial_cookie_value,
                     "cookie_key_5" => :cookie_value_5
                   },
                   __meta__: %Metadata{
                     cookie_ops: %{
                       "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                       "cookie_key_5" => %Cookie{value: :cookie_value_5}
                     }
                   }
                 }
               }
    end

    test "with component and server structs returned from init/3" do
      node = {:component, Module6, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env, @server) ==
               {
                 "<div>state_a = 1, state_b = 2</div>",
                 %{
                   "my_component" => %{module: Module6, struct: %Component{state: %{a: 1, b: 2}}}
                 },
                 %Server{
                   cookies: %{
                     "initial_cookie_key" => :initial_cookie_value,
                     "cookie_key_6" => :cookie_value_6
                   },
                   __meta__: %Metadata{
                     cookie_ops: %{
                       "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                       "cookie_key_6" => %Cookie{value: :cookie_value_6}
                     }
                   }
                 }
               }
    end

    test "with unregistered var used" do
      node =
        {:component, Module18,
         [{"cid", [text: "my_component"]}, {"a", [text: "111"]}, {"c", [text: "333"]}], []}

      assert_raise KeyError,
                   ~r/^key :c not found in: %\{.+\}$/,
                   fn ->
                     render_dom(node, @env, @server)
                   end
    end
  end

  describe "default slot" do
    test "with single node" do
      node = {:component, Module8, [], [text: "123"]}
      assert render_dom(node, @env, @server) == {"abc123xyz", %{}, @server}
    end

    test "with multiple nodes" do
      node = {:component, Module8, [], [text: "123", expression: {456}]}
      assert render_dom(node, @env, @server) == {"abc123456xyz", %{}, @server}
    end

    test "nested components with slots, no slot tag in the top component template, not using vars" do
      node = {:component, Module8, [], [{:component, Module9, [], [text: "789"]}]}
      assert render_dom(node, @env, @server) == {"abcdef789uvwxyz", %{}, @server}
    end

    test "nested components with slots, no slot tag in the top component template, using vars" do
      node = {:component, Module10, [{"cid", [text: "component_10"]}], []}

      assert render_dom(node, @env, @server) ==
               {"10,11,10,12,10",
                %{
                  "component_10" => %{module: Module10, struct: %Component{state: %{a: 10}}},
                  "component_11" => %{module: Module11, struct: %Component{state: %{a: 11}}},
                  "component_12" => %{module: Module12, struct: %Component{state: %{a: 12}}}
                },
                %Server{
                  cookies: %{
                    "initial_cookie_key" => :initial_cookie_value,
                    "cookie_key_10" => :cookie_value_10,
                    "cookie_key_11" => :cookie_value_11,
                    "cookie_key_12" => :cookie_value_12
                  },
                  __meta__: %Metadata{
                    cookie_ops: %{
                      "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                      "cookie_key_10" => %Cookie{value: :cookie_value_10},
                      "cookie_key_11" => %Cookie{value: :cookie_value_11},
                      "cookie_key_12" => %Cookie{value: :cookie_value_12}
                    }
                  }
                }}
    end

    test "nested components with slots, slot tag in the top component template, not using vars" do
      node = {:component, Module31, [], [text: "abc"]}

      assert render_dom(node, @env, @server) ==
               {"31a,32a,31b,33a,31c,abc,31x,33z,31y,32z,31z", %{}, @server}
    end

    test "nested components with slots, slot tag in the top component template, using vars" do
      node =
        {:component, Module34, [{"cid", [text: "component_34"]}, {"a", [text: "34a_prop"]}],
         [text: "abc"]}

      assert render_dom(node, @env, @server) ==
               {"34a_prop,35a_prop,34b_state,36a_prop,34c_state,abc,34x_state,36z_state,34y_state,35z_state,34z_state",
                %{
                  "component_34" => %{
                    module: Module34,
                    struct: %Component{
                      state: %{
                        cid: "component_34",
                        a: "34a_prop",
                        b: "34b_state",
                        c: "34c_state",
                        x: "34x_state",
                        y: "34y_state",
                        z: "34z_state"
                      }
                    }
                  },
                  "component_35" => %{
                    module: Module35,
                    struct: %Component{
                      state: %{cid: "component_35", a: "35a_prop", z: "35z_state"}
                    }
                  },
                  "component_36" => %{
                    module: Module36,
                    struct: %Component{
                      state: %{cid: "component_36", a: "36a_prop", z: "36z_state"}
                    }
                  }
                },
                %Server{
                  cookies: %{
                    "initial_cookie_key" => :initial_cookie_value,
                    "cookie_key_34" => :cookie_value_34,
                    "cookie_key_35" => :cookie_value_35,
                    "cookie_key_36" => :cookie_value_36
                  },
                  __meta__: %Metadata{
                    cookie_ops: %{
                      "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                      "cookie_key_34" => %Cookie{value: :cookie_value_34},
                      "cookie_key_35" => %Cookie{value: :cookie_value_35},
                      "cookie_key_36" => %Cookie{value: :cookie_value_36}
                    }
                  }
                }}
    end

    test "with nested nil node resulting from if block" do
      node = {:component, Module67, [], []}

      {html, component_registry, server_struct} = render_dom(node, @env, @server)

      assert normalize_newlines(html) == "\n  \n"
      assert component_registry == %{}
      assert server_struct == @server
    end
  end

  describe "context" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)

      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "emitted in page, accessed in component nested in page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module39, :dummy_module_39_digest)

      assert render_page(Module39, @params, @server, @opts) ==
               {"prop_aaa = 123",
                %{
                  "layout" => %{
                    module: LayoutFixture,
                    struct: %Component{
                      emitted_context: %{}
                    }
                  },
                  "page" => %{
                    module: Module39,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_39_digest,
                        {Hologram.Runtime, :page_mounted?} => true,
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }, @server}
    end

    test "emitted in page, accessed in component nested in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module46, :dummy_module_46_digest)

      assert render_page(Module46, @params, @server, @opts) ==
               {"prop_aaa = 123",
                %{
                  "layout" => %{
                    module: Module47,
                    struct: %Component{
                      emitted_context: %{}
                    }
                  },
                  "page" => %{
                    module: Module46,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_46_digest,
                        {Hologram.Runtime, :page_mounted?} => true,
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }, @server}
    end

    test "emitted in page, accessed in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module40, :dummy_module_40_digest)

      assert render_page(Module40, @params, @server, @opts) ==
               {"prop_aaa = 123",
                %{
                  "layout" => %{
                    module: Module41,
                    struct: %Component{
                      emitted_context: %{}
                    }
                  },
                  "page" => %{
                    module: Module40,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_40_digest,
                        {Hologram.Runtime, :page_mounted?} => true,
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }, @server}
    end

    test "emmited in layout, accessed in component nested in page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module43, :dummy_module_43_digest)

      assert render_page(Module43, @params, @server, @opts) ==
               {"prop_aaa = 123",
                %{
                  "layout" => %{
                    module: Module42,
                    struct: %Component{
                      emitted_context: %{{:my_scope, :my_key} => 123}
                    }
                  },
                  "page" => %{
                    module: Module43,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_43_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }, @server}
    end

    test "emitted in layout, accessed in component nested in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module45, :dummy_module_45_digest)

      assert render_page(Module45, @params, @server, @opts) ==
               {"prop_aaa = 123",
                %{
                  "layout" => %{
                    module: Module44,
                    struct: %Component{
                      emitted_context: %{{:my_scope, :my_key} => 123}
                    }
                  },
                  "page" => %{
                    module: Module45,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_45_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }, @server}
    end

    test "emitted in component, accessed in component" do
      node = {:component, Module37, [{"cid", [text: "component_37"]}], []}

      assert render_dom(node, @env, @server) ==
               {"prop_aaa = 123",
                %{
                  "component_37" => %{
                    module: Module37,
                    struct: %Component{
                      emitted_context: %{
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }, @server}
    end
  end

  describe "page" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)

      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "inside layout slot" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module14, :dummy_module_14_digest)

      assert {"layout template start, page template, layout template end", _component_registry,
              _server_struct} =
               render_page(Module14, @params, @server, @opts)
    end

    test "cast page param values to correct type" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module19, :dummy_module_19_digest)

      params = %{param_1: "abc", param_3: 123}

      assert {~s'page vars = %{param_1: &quot;abc&quot;, param_3: 123}', _component_registry,
              _server_struct} =
               render_page(Module19, params, @server, @opts)
    end

    test "cast layout explicit static props" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module25, :dummy_module_25_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;prop_value_1&quot;, prop_3: &quot;prop_value_3&quot;}',
              _component_registry,
              _server_struct} = render_page(Module25, @params, @server, @opts)
    end

    test "cast layout props passed implicitely from page state" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module27, :dummy_module_27_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;prop_value_1&quot;, prop_3: &quot;prop_value_3&quot;}',
              _component_registry,
              _server_struct} = render_page(Module27, @params, @server, @opts)
    end

    test "aggregate page vars, giving state vars priority over param vars when there are name conflicts" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module21, :dummy_module_21_digest)

      params = %{key_1: "param_value_1", key_2: "param_value_2"}

      assert {~s'page vars = %{key_1: &quot;param_value_1&quot;, key_2: &quot;state_value_2&quot;, key_3: &quot;state_value_3&quot;}',
              _component_registry, _server_struct} = render_page(Module21, params, @server, @opts)
    end

    test "aggregate layout vars, giving state vars priority over prop vars when there are name conflicts" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module24, :dummy_module_24_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, key_1: &quot;prop_value_1&quot;, key_2: &quot;state_value_2&quot;, key_3: &quot;state_value_3&quot;}',
              _component_registry,
              _server_struct} = render_page(Module24, @params, @server, @opts)
    end

    test "merge the page component struct into the result" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      assert render_page(Module28, @params, @server, @opts) ==
               {"",
                %{
                  "layout" => %{module: LayoutFixture, struct: %Component{}},
                  "page" => %{
                    module: Module28,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_28_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      },
                      state: %{state_1: "value_1", state_2: "value_2"}
                    }
                  }
                }, @server}
    end

    test "merge the layout component struct into the result" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module29, :dummy_module_29_digest)

      assert render_page(Module29, @params, @server, @opts) ==
               {"",
                %{
                  "layout" => %{
                    module: Module30,
                    struct: %Component{
                      state: %{state_1: "value_1", state_2: "value_2"}
                    }
                  },
                  "page" => %{
                    module: Module29,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_29_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }, @server}
    end

    test "passes server struct to layout and nested components and aggregates mutations" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module70, :dummy_module_70_digest)

      {_html, _component_registry, server_struct} = render_page(Module70, @params, @server, @opts)

      assert server_struct == %Server{
               cookies: %{
                 "initial_cookie_key" => :initial_cookie_value,
                 "cookie_key_page" => :cookie_value_page,
                 "cookie_key_layout" => :cookie_value_layout,
                 "cookie_key_72" => :cookie_value_72,
                 "cookie_key_73" => :cookie_value_73,
                 "cookie_key_74" => :cookie_value_74,
                 "cookie_key_75" => :cookie_value_75
               },
               __meta__: %Metadata{
                 cookie_ops: %{
                   "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                   "cookie_key_page" => %Cookie{value: :cookie_value_page},
                   "cookie_key_layout" => %Cookie{value: :cookie_value_layout},
                   "cookie_key_72" => %Cookie{value: :cookie_value_72},
                   "cookie_key_73" => %Cookie{value: :cookie_value_73},
                   "cookie_key_74" => %Cookie{value: :cookie_value_74},
                   "cookie_key_75" => %Cookie{value: :cookie_value_75}
                 }
               }
             }
    end

    test "injects (interpolated) asset manifest when the initial_page? opt is set to true" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module53, :dummy_module_53_digest)

      opts = [csrf_token: @csrf_token, initial_page?: true]

      assert {html, _component_registry, _server_struct} =
               render_page(Module53, @params, @server, opts)

      assert normalize_newlines(html) =~
               ~r'globalThis.hologram.assetManifest = \{\n"hologram/runtime\.js": "/hologram/runtime\-1234567890abcdef\.js"[^\}]+\n\};'
    end

    test "doesn't inject asset manifest when the initial_page? opt is set to false" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module53, :dummy_module_53_digest)

      opts = [csrf_token: @csrf_token, initial_page?: false]

      assert {html, _component_registry, _server_struct} =
               render_page(Module53, @params, @server, opts)

      refute String.contains?(html, "globalThis.hologram.assetManifest")
    end

    test "interpolate component structs JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page(Module48, @params, @server, @opts)

      expected =
        ~s/componentRegistry: Type.map([[Type.bitstring("layout"), Type.map([[Type.atom("module"), Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module49")], [Type.atom("struct"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")], [Type.atom("emitted_context"), Type.map([])], [Type.atom("next_action"), Type.atom("nil")], [Type.atom("next_command"), Type.atom("nil")], [Type.atom("next_page"), Type.atom("nil")], [Type.atom("state"), Type.map([])]])]])], [Type.bitstring("page"), Type.map([[Type.atom("module"), Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module48")], [Type.atom("struct"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")], [Type.atom("emitted_context"), Type.map([[Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("csrf_token")]), Type.bitstring("#{@csrf_token}")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("initial_page?")]), Type.atom("false")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("page_digest")]), Type.bitstring("102790adb6c3b1956db310be523a7693")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("page_mounted?")]), Type.atom("true")]])], [Type.atom("next_action"), Type.atom("nil")], [Type.atom("next_command"), Type.atom("nil")], [Type.atom("next_page"), Type.atom("nil")], [Type.atom("state"), Type.map([])]])]])]])/

      assert String.contains?(html, expected)
    end

    test "interpolate page module JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page(Module48, @params, @server, @opts)

      expected =
        ~s/pageModule: Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module48")/

      assert String.contains?(html, expected)
    end

    test "interpolate page params JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module50,
        "102790adb6c3b1956db310be523a7693"
      )

      params = %{key_1: 123, key_2: "value_2"}

      assert {html, _component_registry, _server_struct} =
               render_page(Module50, params, @server, @opts)

      expected =
        ~s/pageParams: Type.map([[Type.atom("key_1"), Type.integer(123n)], [Type.atom("key_2"), Type.bitstring("value_2")]])/

      assert String.contains?(html, expected)
    end

    test "with DOCTYPE" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module62,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page(Module62, @params, @server, @opts)

      expected_html = """
      <!DOCTYPE html>
      <html>
        <body>
          Module62
        </body>
      </html>\
      """

      assert normalize_newlines(html) == normalize_newlines(expected_html)
    end

    test "CSRF token is put into page emitted context for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: @csrf_token, initial_page?: true]

      assert {_html, component_registry, _server_struct} =
               render_page(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      assert page_emitted_context[{Hologram.Runtime, :csrf_token}] == @csrf_token
    end

    test "CSRF token is not put into page emitted context for subsequent page requests even when provided" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: @csrf_token, initial_page?: false]

      assert {_html, component_registry, _server_struct} =
               render_page(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      refute Map.has_key?(page_emitted_context, {Hologram.Runtime, :csrf_token})
    end

    test "raises ArgumentError when CSRF token is not provided for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [initial_page?: true]

      assert_raise ArgumentError, "CSRF token is required for initial page requests", fn ->
        render_page(Module28, @params, @server, opts)
      end
    end

    test "raises ArgumentError when CSRF token is nil for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: nil, initial_page?: true]

      assert_raise ArgumentError, "CSRF token is required for initial page requests", fn ->
        render_page(Module28, @params, @server, opts)
      end
    end

    test "CSRF token is not required for subsequent page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [initial_page?: false]

      assert {_html, component_registry, _server_struct} =
               render_page(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      refute Map.has_key?(page_emitted_context, {Hologram.Runtime, :csrf_token})
    end
  end

  # IMPORTANT!
  # Keep client-side Renderer "escaping" and server-side Renderer "escaping" unit tests consistent.
  #
  # Note: the behaviour is different on client-side vs server-side
  # because client-side escaping is delegated to Snabbdom
  describe "escaping" do
    test "text inside non-script elements" do
      # <div>abc < xyz</div>
      node = {:element, "div", [], [text: "abc < xyz"]}

      assert render_dom(node, @env, @server) == {"<div>abc &lt; xyz</div>", %{}, @server}
    end

    test "text inside script elements" do
      # <script>abc < xyz</script>
      node = {:element, "script", [], [text: "abc < xyz"]}

      assert render_dom(node, @env, @server) == {"<script>abc < xyz</script>", %{}, @server}
    end

    test "text inside public comments" do
      # <!-- abc < xyz -->
      node = {:public_comment, [text: " abc < xyz "]}

      assert render_dom(node, @env, @server) == {"<!-- abc &lt; xyz -->", %{}, @server}
    end

    test "text inside attribute" do
      # <div class="abc < xyz"></div>
      node = {:element, "div", [{"class", [text: "abc < xyz"]}], []}

      assert render_dom(node, @env, @server) ==
               {~s'<div class="abc &lt; xyz"></div>', %{}, @server}
    end

    test "expression inside non-script elements" do
      # <div>{"abc < xyz"}</div>
      node = {:element, "div", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env, @server) == {"<div>abc &lt; xyz</div>", %{}, @server}
    end

    test "expression inside script elements" do
      # <script>{"abc < xyz"}</script>
      node = {:element, "script", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env, @server) == {"<script>abc &lt; xyz</script>", %{}, @server}
    end

    test "expression inside public comments" do
      # <!-- {"abc < xyz"} -->
      node = {:public_comment, [text: " ", expression: {"abc < xyz"}, text: " "]}

      assert render_dom(node, @env, @server) == {"<!-- abc &lt; xyz -->", %{}, @server}
    end

    test "expression inside non-input attribute" do
      # <div class={"abc < xyz"}></div>
      node = {:element, "div", [{"class", [expression: {"abc < xyz"}]}], []}

      assert render_dom(node, @env, @server) ==
               {~s'<div class="abc &lt; xyz"></div>', %{}, @server}
    end

    test "expression inside input non-controlled attribute" do
      # <input type="text" class={"abc < xyz"} />
      node =
        {:element, "input", [{"type", [text: "text"]}, {"class", [expression: {"abc < xyz"}]}],
         []}

      assert render_dom(node, @env, @server) ==
               {~s'<input type="text" class="abc &lt; xyz" />', %{}, @server}
    end

    test "multi-part attribute" do
      # <div class="a < b {"< c <"} d < e"></div>
      node =
        {:element, "div", [{"class", [text: "a < b ", expression: {"< c <"}, text: " d < e"]}],
         []}

      assert render_dom(node, @env, @server) ==
               {~s'<div class="a &lt; b &lt; c &lt; d &lt; e"></div>', %{}, @server}
    end
  end

  describe "stringify_for_interpolation/1" do
    test "atom, non-boolean and non-nil" do
      assert stringify_for_interpolation(:abc) == "abc"
    end

    test "atom, true" do
      assert stringify_for_interpolation(true) == "true"
    end

    test "atom, false" do
      assert stringify_for_interpolation(false) == "false"
    end

    test "atom, nil" do
      assert stringify_for_interpolation(nil) == ""
    end

    test "bitstring, binary" do
      assert stringify_for_interpolation(<<97, 98, 99>>) == "abc"
    end

    test "bitstring, non-binary" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type BitString/,
                   fn ->
                     stringify_for_interpolation(<<97::6, 98::4>>)
                   end
    end

    test "float" do
      assert stringify_for_interpolation(1.23) == "1.23"
    end

    test "function, anonymous" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Function/,
                   fn ->
                     stringify_for_interpolation(fn x, y -> x + y end)
                   end
    end

    test "function, captured" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Function/,
                   fn ->
                     stringify_for_interpolation(&Map.put/3)
                   end
    end

    test "integer" do
      assert stringify_for_interpolation(123) == "123"
    end

    test "list, strings" do
      assert stringify_for_interpolation(["ab", "cd"]) == "abcd"
    end

    test "list, Unicode code points" do
      assert stringify_for_interpolation([97, 98, 99]) == "abc"
    end

    test "list, not stringifiable" do
      assert_error ArgumentError, ~r/cannot convert the given list to a string/, fn ->
        stringify_for_interpolation([1, nil, 2])
      end
    end

    test "map, atom keys" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Map/,
                   fn ->
                     stringify_for_interpolation(%{a: 1, b: 2})
                   end
    end

    test "map, mixed keys" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Map/,
                   fn ->
                     stringify_for_interpolation(%{:a => 1, "b" => nil, 2 => 3})
                   end
    end

    test "PID" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type PID/,
                   fn ->
                     stringify_for_interpolation(pid("0.11.222"))
                   end
    end

    test "port" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Port/,
                   fn ->
                     stringify_for_interpolation(port("0.11"))
                   end
    end

    test "reference" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Reference/,
                   fn ->
                     stringify_for_interpolation(ref("0.1.2.3"))
                   end
    end

    test "struct, having String.Chars protocol implementation" do
      value = %Version{major: 1, minor: 2, patch: 3}

      assert stringify_for_interpolation(value) == "1.2.3"
    end

    test "struct, not having String.Chars protocol implementation" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type MapSet \(a struct\)/,
                   fn ->
                     stringify_for_interpolation(MapSet.new([1, 2, 3]))
                   end
    end

    test "tuple" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for type Tuple/,
                   fn ->
                     stringify_for_interpolation({97, 98, 99})
                   end
    end
  end
end
