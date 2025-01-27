defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Component
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
  alias Hologram.Test.Fixtures.Template.Renderer.Module7
  alias Hologram.Test.Fixtures.Template.Renderer.Module8
  alias Hologram.Test.Fixtures.Template.Renderer.Module9

  @env %Renderer.Env{}
  @opts [initial_page?: true]
  @params %{}

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  test "text node" do
    node = {:text, "Tom & Jerry"}
    assert render_dom(node, @env) == {"Tom &amp; Jerry", %{}}
  end

  describe "public comment node" do
    test "empty" do
      # <!---->
      node = {:public_comment, []}

      assert render_dom(node, @env) == {"<!---->", %{}}
    end

    test "with single child" do
      # <!--<div></div>-->
      node = {:public_comment, [{:element, "div", [], []}]}

      assert render_dom(node, @env) == {"<!--<div></div>-->", %{}}
    end

    test "with multiple children" do
      # <!--abc<div></div>-->
      node = {:public_comment, [{:text, "abc"}, {:element, "div", [], []}]}

      assert render_dom(node, @env) == {"<!--abc<div></div>-->", %{}}
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

      assert render_dom(node, @env) ==
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
                }}
    end

    test "HTML entities inside public comments are not escaped" do
      # <!-- abc < xyz -->
      node = {:public_comment, [text: " abc < xyz "]}

      assert render_dom(node, @env) == {"<!-- abc < xyz -->", %{}}
    end
  end

  test "DOCTYPE node" do
    node = {:doctype, "html"}
    assert render_dom(node, @env) == {"<!DOCTYPE html>", %{}}
  end

  describe "expression node" do
    test "expression value is converted to string" do
      # {123}
      node = {:expression, {123}}

      assert render_dom(node, @env) == {"123", %{}}
    end

    test "HTML entities inside script elements are not escaped" do
      # <script>{"abc < xyz"}</script>
      node = {:element, "script", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env) == {"<script>abc < xyz</script>", %{}}
    end

    test "HTML entities inside non-script elements are escaped" do
      # <div>{"abc < xyz"}</div>
      node = {:element, "div", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env) == {"<div>abc &lt; xyz</div>", %{}}
    end
  end

  describe "element node" do
    test "non-void element, without attributes or children" do
      node = {:element, "div", [], []}
      assert render_dom(node, @env) == {"<div></div>", %{}}
    end

    test "non-void element, with attributes" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render_dom(node, @env) ==
               {~s(<div attr_1="aaa" attr_2="123" attr_3="ccc987eee"></div>), %{}}
    end

    test "non-void element, with children" do
      node = {:element, "div", [], [{:element, "span", [], [text: "abc"]}, {:text, "xyz"}]}
      assert render_dom(node, @env) == {"<div><span>abc</span>xyz</div>", %{}}
    end

    test "void element, without attributes" do
      node = {:element, "img", [], []}
      assert render_dom(node, @env) == {"<img />", %{}}
    end

    test "void element, with attributes" do
      node =
        {:element, "img",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render_dom(node, @env) ==
               {~s(<img attr_1="aaa" attr_2="123" attr_3="ccc987eee" />), %{}}
    end

    test "boolean attributes" do
      node = {:element, "img", [{"attr_1", []}, {"attr_2", [text: ""]}], []}
      assert render_dom(node, @env) == {~s(<img attr_1 attr_2 />), %{}}
    end

    test "attributes that evaluate to nil are not rendered" do
      node =
        {:element, "img",
         [
           {"attr_1", [expression: {nil}]},
           {"attr_2", [expression: {"value_2"}]},
           {"attr_3", [expression: {nil}]}
         ], []}

      assert render_dom(node, @env) == {~s(<img attr_2="value_2" />), %{}}
    end

    test "if there are no attributes to render there is no whitespace inside the tag, non-void element" do
      node =
        {:element, "div",
         [
           {"attr_1", [expression: {nil}]},
           {"attr_2", [expression: {nil}]}
         ], []}

      assert render_dom(node, @env) == {~s(<div></div>), %{}}
    end

    test "if there are no attributes to render there is no whitespace inside the tag, void element" do
      node =
        {:element, "img",
         [
           {"attr_1", [expression: {nil}]},
           {"attr_2", [expression: {nil}]}
         ], []}

      assert render_dom(node, @env) == {~s(<img />), %{}}
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

      assert render_dom(node, @env) ==
               {~s(<div attr_1="aaa" attr_3="111" attr_5="ccc999ddd" attr_7></div>), %{}}
    end

    test "with nested stateful components" do
      node =
        {:element, "div", [{"attr", [text: "value"]}],
         [
           {:component, Module3, [{"cid", [text: "component_3"]}], []},
           {:component, Module7, [{"cid", [text: "component_7"]}], []}
         ]}

      assert render_dom(node, @env) ==
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
                }}
    end

    test "HTML entities inside script tags are not escaped" do
      # <script>abc < xyz</script>
      node = {:element, "script", [], [text: "abc < xyz"]}

      assert render_dom(node, @env) == {"<script>abc < xyz</script>", %{}}
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

      assert render_dom(nodes, @env) == {"aaa111bbb222", %{}}
    end

    test "nil nodes" do
      nodes = [
        {:text, "abc"},
        nil,
        {:text, "xyz"},
        nil
      ]

      assert render_dom(nodes, @env) == {"abcxyz", %{}}
    end

    test "with components having a root node" do
      nodes = [
        {:text, "abc"},
        {:component, Module3, [{"cid", [text: "component_3"]}], []},
        {:text, "xyz"},
        {:component, Module7, [{"cid", [text: "component_7"]}], []}
      ]

      assert render_dom(nodes, @env) ==
               {"abc<div>state_a = 1, state_b = 2</div>xyz<div>state_c = 3, state_d = 4</div>",
                %{
                  "component_3" => %{module: Module3, struct: %Component{state: %{a: 1, b: 2}}},
                  "component_7" => %{module: Module7, struct: %Component{state: %{c: 3, d: 4}}}
                }}
    end

    test "with components not having a root node" do
      nodes = [
        {:text, "abc"},
        {:component, Module51, [{"cid", [text: "component_51"]}], []},
        {:text, "xyz"},
        {:component, Module52, [{"cid", [text: "component_52"]}], []}
      ]

      assert render_dom(nodes, @env) ==
               {"abc<div>state_a = 1</div><div>state_b = 2</div>xyz<div>state_c = 3</div><div>state_d = 4</div>",
                %{
                  "component_51" => %{module: Module51, struct: %Component{state: %{a: 1, b: 2}}},
                  "component_52" => %{module: Module52, struct: %Component{state: %{c: 3, d: 4}}}
                }}
    end
  end

  describe "component props" do
    test "single-valued" do
      node = {:component, Module64, [{"my_prop", [expression: {123}]}], []}
      assert render_dom(node, @env) == {"my_prop = 123", %{}}
    end

    test "multi-valued" do
      node = {:component, Module64, [{"my_prop", [expression: {1, 2, 3}]}], []}
      assert render_dom(node, @env) == {"my_prop = {1, 2, 3}", %{}}
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
              _component_registry} = render_dom(node, @env)
    end

    test "default value specified" do
      node = {:component, Module65, [{"prop_2", [expression: {:xyz}]}], []}

      assert {~s'component vars = %{prop_1: &quot;abc&quot;, prop_2: :xyz, prop_3: 123}',
              _component_registry} = render_dom(node, @env)
    end

    test "default value not specified" do
      node = {:component, Module66, [{"prop_2", [expression: {:xyz}]}], []}

      assert {~s'component vars = %{prop_2: :xyz}', _component_registry} = render_dom(node, @env)
    end
  end

  describe "stateless component" do
    test "without props" do
      node = {:component, Module1, [], []}
      assert render_dom(node, @env) == {"<div>abc</div>", %{}}
    end

    test "with props" do
      node =
        {:component, Module2,
         [
           {"a", [text: "ddd"]},
           {"b", [expression: {222}]},
           {"c", [text: "fff", expression: {333}, text: "hhh"]}
         ], []}

      assert render_dom(node, @env) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>", %{}}
    end

    test "with unregistered var used" do
      node = {:component, Module17, [{"a", [text: "111"]}, {"b", [text: "222"]}], []}

      expected_msg = build_key_error_msg(:b, %{a: "111"})

      assert_raise KeyError, expected_msg, fn ->
        render_dom(node, @env)
      end
    end
  end

  # Some client tests are different than server tests.
  describe "stateful component" do
    test "without props or state" do
      node = {:component, Module1, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env) ==
               {"<div>abc</div>",
                %{"my_component" => %{module: Module1, struct: %Component{state: %{}}}}}
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

      assert render_dom(node, @env) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>",
                %{"my_component" => %{module: Module2, struct: %Component{state: %{}}}}}
    end

    test "with state / only component struct returned from init/3" do
      node = {:component, Module3, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %{module: Module3, struct: %Component{state: %{a: 1, b: 2}}}}}
    end

    test "with props and state, give state priority over prop if there are name collisions" do
      node =
        {:component, Module4,
         [
           {"cid", [text: "my_component"]},
           {"b", [text: "prop_b"]},
           {"c", [text: "prop_c"]}
         ], []}

      assert render_dom(node, @env) ==
               {"<div>var_a = state_a, var_b = state_b, var_c = prop_c</div>",
                %{
                  "my_component" => %{
                    module: Module4,
                    struct: %Component{state: %{a: "state_a", b: "state_b"}}
                  }
                }}
    end

    test "with only server struct returned from init/3" do
      node =
        {:component, Module5,
         [
           {"cid", [text: "my_component"]},
           {"a", [text: "aaa"]},
           {"b", [text: "bbb"]}
         ], []}

      assert render_dom(node, @env) ==
               {"<div>prop_a = aaa, prop_b = bbb</div>",
                %{"my_component" => %{module: Module5, struct: %Component{state: %{}}}}}
    end

    test "with component and server structs returned from init/3" do
      node = {:component, Module6, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %{module: Module6, struct: %Component{state: %{a: 1, b: 2}}}}}
    end

    test "with unregistered var used" do
      node =
        {:component, Module18,
         [{"cid", [text: "my_component"]}, {"a", [text: "111"]}, {"c", [text: "333"]}], []}

      assert_raise KeyError,
                   ~r/^key :c not found in: %\{.+\}$/,
                   fn ->
                     render_dom(node, @env)
                   end
    end
  end

  describe "default slot" do
    test "with single node" do
      node = {:component, Module8, [], [text: "123"]}
      assert render_dom(node, @env) == {"abc123xyz", %{}}
    end

    test "with multiple nodes" do
      node = {:component, Module8, [], [text: "123", expression: {456}]}
      assert render_dom(node, @env) == {"abc123456xyz", %{}}
    end

    test "nested components with slots, no slot tag in the top component template, not using vars" do
      node = {:component, Module8, [], [{:component, Module9, [], [text: "789"]}]}
      assert render_dom(node, @env) == {"abcdef789uvwxyz", %{}}
    end

    test "nested components with slots, no slot tag in the top component template, using vars" do
      node = {:component, Module10, [{"cid", [text: "component_10"]}], []}

      assert render_dom(node, @env) ==
               {"10,11,10,12,10",
                %{
                  "component_10" => %{module: Module10, struct: %Component{state: %{a: 10}}},
                  "component_11" => %{module: Module11, struct: %Component{state: %{a: 11}}},
                  "component_12" => %{module: Module12, struct: %Component{state: %{a: 12}}}
                }}
    end

    test "nested components with slots, slot tag in the top component template, not using vars" do
      node = {:component, Module31, [], [text: "abc"]}

      assert render_dom(node, @env) == {"31a,32a,31b,33a,31c,abc,31x,33z,31y,32z,31z", %{}}
    end

    test "nested components with slots, slot tag in the top component template, using vars" do
      node =
        {:component, Module34, [{"cid", [text: "component_34"]}, {"a", [text: "34a_prop"]}],
         [text: "abc"]}

      assert render_dom(node, @env) ==
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
                }}
    end
  end

  describe "context" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "emitted in page, accessed in component nested in page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module39, :dummy_module_39_digest)

      assert render_page(Module39, @params, @opts) ==
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
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_39_digest,
                        {Hologram.Runtime, :page_mounted?} => true,
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }}
    end

    test "emitted in page, accessed in component nested in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module46, :dummy_module_46_digest)

      assert render_page(Module46, @params, @opts) ==
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
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_46_digest,
                        {Hologram.Runtime, :page_mounted?} => true,
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }}
    end

    test "emitted in page, accessed in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module40, :dummy_module_40_digest)

      assert render_page(Module40, @params, @opts) ==
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
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_40_digest,
                        {Hologram.Runtime, :page_mounted?} => true,
                        {:my_scope, :my_key} => 123
                      }
                    }
                  }
                }}
    end

    test "emmited in layout, accessed in component nested in page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module43, :dummy_module_43_digest)

      assert render_page(Module43, @params, @opts) ==
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
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_43_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }}
    end

    test "emitted in layout, accessed in component nested in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module45, :dummy_module_45_digest)

      assert render_page(Module45, @params, @opts) ==
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
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_45_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }}
    end

    test "emitted in component, accessed in component" do
      node = {:component, Module37, [{"cid", [text: "component_37"]}], []}

      assert render_dom(node, @env) ==
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
                }}
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

      assert {"layout template start, page template, layout template end", _component_registry} =
               render_page(Module14, @params, @opts)
    end

    test "raises Hologram.ParamError when extraneous params are given" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module19, :dummy_module_19_digest)

      params = %{param_1: "abc", param_2: "value_2", param_3: "123"}

      assert_raise Hologram.ParamError,
                   ~s/page "Hologram.Test.Fixtures.Template.Renderer.Module19" doesn't expect "param_2" param/,
                   fn ->
                     render_page(Module19, params, @opts)
                   end
    end

    test "cast page param values to correct type" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module19, :dummy_module_19_digest)

      params = %{param_1: "abc", param_3: "123"}

      assert {~s'page vars = %{param_1: &quot;abc&quot;, param_3: 123}', _component_registry} =
               render_page(Module19, params, @opts)
    end

    test "cast layout explicit static props" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module25, :dummy_module_25_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;prop_value_1&quot;, prop_3: &quot;prop_value_3&quot;}',
              _component_registry} = render_page(Module25, @params, @opts)
    end

    test "cast layout props passed implicitely from page state" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module27, :dummy_module_27_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;prop_value_1&quot;, prop_3: &quot;prop_value_3&quot;}',
              _component_registry} = render_page(Module27, @params, @opts)
    end

    test "aggregate page vars, giving state vars priority over param vars when there are name conflicts" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module21, :dummy_module_21_digest)

      params = %{key_1: "param_value_1", key_2: "param_value_2"}

      assert {~s'page vars = %{key_1: &quot;param_value_1&quot;, key_2: &quot;state_value_2&quot;, key_3: &quot;state_value_3&quot;}',
              _component_registry} = render_page(Module21, params, @opts)
    end

    test "aggregate layout vars, giving state vars priority over prop vars when there are name conflicts" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module24, :dummy_module_24_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, key_1: &quot;prop_value_1&quot;, key_2: &quot;state_value_2&quot;, key_3: &quot;state_value_3&quot;}',
              _component_registry} = render_page(Module24, @params, @opts)
    end

    test "merge the page component struct into the result" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      assert render_page(Module28, @params, @opts) ==
               {"",
                %{
                  "layout" => %{module: LayoutFixture, struct: %Component{}},
                  "page" => %{
                    module: Module28,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_28_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      },
                      state: %{state_1: "value_1", state_2: "value_2"}
                    }
                  }
                }}
    end

    test "merge the layout component struct into the result" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module29, :dummy_module_29_digest)

      assert render_page(Module29, @params, @opts) ==
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
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :page_digest} => :dummy_module_29_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }}
    end

    test "injects asset manifest when the initial_page? opt is set to true" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module53, :dummy_module_53_digest)

      assert {html, _component_registry} = render_page(Module53, @params, initial_page?: true)

      assert String.contains?(html, "globalThis.hologram.assetManifest")
    end

    test "doesn't inject asset manifest when the initial_page? opt is set to false" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module53, :dummy_module_53_digest)

      assert {html, _component_registry} = render_page(Module53, @params, initial_page?: false)

      refute String.contains?(html, "globalThis.hologram.assetManifest")
    end

    test "interpolate component structs JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry} = render_page(Module48, @params, @opts)

      expected =
        ~s/componentRegistry: Type.map([[Type.bitstring("layout"), Type.map([[Type.atom("module"), Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module49")], [Type.atom("struct"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")], [Type.atom("emitted_context"), Type.map([])], [Type.atom("next_action"), Type.atom("nil")], [Type.atom("next_command"), Type.atom("nil")], [Type.atom("next_page"), Type.atom("nil")], [Type.atom("state"), Type.map([])]])]])], [Type.bitstring("page"), Type.map([[Type.atom("module"), Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module48")], [Type.atom("struct"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")], [Type.atom("emitted_context"), Type.map([[Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("initial_page?")]), Type.atom("false")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("page_digest")]), Type.bitstring("102790adb6c3b1956db310be523a7693")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("page_mounted?")]), Type.atom("true")]])], [Type.atom("next_action"), Type.atom("nil")], [Type.atom("next_command"), Type.atom("nil")], [Type.atom("next_page"), Type.atom("nil")], [Type.atom("state"), Type.map([])]])]])]])/

      assert String.contains?(html, expected)
    end

    test "interpolate page module JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry} = render_page(Module48, @params, @opts)

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

      params = %{key_1: "123", key_2: "value_2"}

      assert {html, _component_registry} = render_page(Module50, params, @opts)

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

      assert {html, _component_registry} = render_page(Module62, @params, @opts)

      assert html == """
             <!DOCTYPE html>
             <html>
               <body>
                 Module62
               </body>
             </html>\
             """
    end
  end
end
