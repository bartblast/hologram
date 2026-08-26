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
  alias Hologram.Server.Broadcast
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
  alias Hologram.Test.Fixtures.Template.Renderer.Module79
  alias Hologram.Test.Fixtures.Template.Renderer.Module8
  alias Hologram.Test.Fixtures.Template.Renderer.Module80
  alias Hologram.Test.Fixtures.Template.Renderer.Module84
  alias Hologram.Test.Fixtures.Template.Renderer.Module86
  alias Hologram.Test.Fixtures.Template.Renderer.Module87
  alias Hologram.Test.Fixtures.Template.Renderer.Module88
  alias Hologram.Test.Fixtures.Template.Renderer.Module89
  alias Hologram.Test.Fixtures.Template.Renderer.Module9
  alias Hologram.Test.Fixtures.Template.Renderer.Module90
  alias Hologram.Test.Fixtures.Template.Renderer.Module91
  alias Hologram.Test.Fixtures.Template.Renderer.Module92

  @csrf_token "test-csrf-token"
  @env %Renderer.Env{}
  @instance_id "test-instance-id"
  @opts [csrf_token: @csrf_token, initial_page?: true, instance_id: @instance_id]
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
           {"$attr_8", []},
           {"$attr_9", [text: "ggg"], ["mod_1"]}
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

  describe "element spread" do
    test "map value" do
      # <div ...{%{id: "my_id"}}></div>
      node = {:element, "div", [{:spread, {%{id: "my_id"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_id"></div>), %{}, @server}
    end

    test "keyword list value" do
      node = {:element, "div", [{:spread, {[id: "my_id", class: "my_class"]}}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div class="my_class" id="my_id"></div>), %{}, @server}
    end

    test "map value with multiple entries" do
      node = {:element, "div", [{:spread, {%{id: "my_id", class: "my_class"}}}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div class="my_class" id="my_id"></div>), %{}, @server}
    end

    test "string keys" do
      node = {:element, "div", [{:spread, {%{"id" => "my_id"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_id"></div>), %{}, @server}
    end

    test "entries are sorted by name, regardless of key type" do
      node =
        {:element, "div", [{:spread, {%{:my_key_3 => "c", "my_key_1" => "a", :my_key_2 => "b"}}}],
         []}

      assert render_dom(node, @env, @server) ==
               {~s(<div my-key-1="a" my-key-2="b" my-key-3="c"></div>), %{}, @server}
    end

    test "entries are sorted by the composed name, so nested ones stay next to their siblings" do
      node =
        {:element, "div",
         [{:spread, {[my_key_2: "b", data: [user_id: 1, role: "admin"], my_key_1: "a"]}}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div data-role="admin" data-user-id="1" my-key-1="a" my-key-2="b"></div>), %{},
                @server}
    end

    # Only the block a single spread expands to is sorted.
    test "sorting doesn't move attributes written literally" do
      node =
        {:element, "div",
         [
           {"zzz", [text: "my_value_1"]},
           {:spread, {%{bbb: "my_value_2", aaa: "my_value_3"}}},
           {"yyy", [text: "my_value_4"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div zzz="my_value_1" aaa="my_value_3" bbb="my_value_2" yyy="my_value_4"></div>),
                %{}, @server}
    end

    test "each spread is sorted on its own" do
      node =
        {:element, "div",
         [
           {:spread, {%{zzz: "my_value_1", aaa: "my_value_2"}}},
           {:spread, {%{bbb: "my_value_3"}}}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div aaa="my_value_2" zzz="my_value_1" bbb="my_value_3"></div>), %{}, @server}
    end

    test "underscores in an atom key are converted to hyphens" do
      node = {:element, "div", [{:spread, {%{my_key: "my_value"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div my-key="my_value"></div>), %{}, @server}
    end

    test "underscores in a string key are converted to hyphens" do
      node = {:element, "div", [{:spread, {%{"my_key" => "my_value"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div my-key="my_value"></div>), %{}, @server}
    end

    test "nested map value composes a dash-joined name" do
      node = {:element, "div", [{:spread, {%{data: %{user_id: 1}}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div data-user-id="1"></div>), %{}, @server}
    end

    test "nested keyword list value composes a dash-joined name" do
      node = {:element, "div", [{:spread, {[data: [user_id: 1]]}}], []}

      assert render_dom(node, @env, @server) == {~s(<div data-user-id="1"></div>), %{}, @server}
    end

    test "map nested in a keyword list" do
      node = {:element, "div", [{:spread, {[data: %{user_id: 1}]}}], []}

      assert render_dom(node, @env, @server) == {~s(<div data-user-id="1"></div>), %{}, @server}
    end

    test "keyword list nested in a map" do
      node = {:element, "div", [{:spread, {%{data: [user_id: 1]}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div data-user-id="1"></div>), %{}, @server}
    end

    test "nesting at multiple levels" do
      node = {:element, "div", [{:spread, {[data: [my_group: %{my_key: "my_value"}]]}}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div data-my-group-my-key="my_value"></div>), %{}, @server}
    end

    # Sorting is stable, so a keyword list's order still decides which duplicate key wins.
    test "duplicate keys in a keyword list, later wins" do
      node = {:element, "div", [{:spread, {[id: "my_value_1", id: "my_value_2"]}}], []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_value_2"></div>), %{}, @server}
    end

    test "entry with nil value is not rendered" do
      node = {:element, "div", [{:spread, {[id: nil, class: "my_class"]}}], []}

      assert render_dom(node, @env, @server) == {~s(<div class="my_class"></div>), %{}, @server}
    end

    test "entry with false value is not rendered" do
      node = {:element, "div", [{:spread, {[id: false, class: "my_class"]}}], []}

      assert render_dom(node, @env, @server) == {~s(<div class="my_class"></div>), %{}, @server}
    end

    test "entry with true value is stringified, same as a named attribute" do
      node = {:element, "div", [{:spread, {%{id: true}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div id="true"></div>), %{}, @server}
    end

    test "entry with empty string value renders the bare name, same as a named attribute" do
      node = {:element, "div", [{:spread, {%{id: ""}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div id></div>), %{}, @server}
    end

    test "struct entry value is a leaf and is stringified" do
      node = {:element, "div", [{:spread, {%{my_key: ~D[2024-01-15]}}}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div my-key="2024-01-15"></div>), %{}, @server}
    end

    # Only maps and keyword lists recurse, so a non-keyword list nested inside a spread is a value.
    test "nested list which is not a keyword list is a leaf and is stringified" do
      node = {:element, "div", [{:spread, {%{my_key: ~c"abc"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div my-key="abc"></div>), %{}, @server}
    end

    test "empty map value renders no attributes" do
      node = {:element, "div", [{:spread, {%{}}}], []}

      assert render_dom(node, @env, @server) == {"<div></div>", %{}, @server}
    end

    test "empty keyword list value renders no attributes" do
      node = {:element, "div", [{:spread, {[]}}], []}

      assert render_dom(node, @env, @server) == {"<div></div>", %{}, @server}
    end

    test "void element" do
      node = {:element, "img", [{:spread, {%{id: "my_id"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<img id="my_id" />), %{}, @server}
    end

    test "named attribute before the spread is overridden" do
      node =
        {:element, "div", [{"id", [text: "my_value_1"]}, {:spread, {%{id: "my_value_2"}}}], []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_value_2"></div>), %{}, @server}
    end

    test "named attribute after the spread wins" do
      node =
        {:element, "div", [{:spread, {%{id: "my_value_1"}}}, {"id", [text: "my_value_2"]}], []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_value_2"></div>), %{}, @server}
    end

    test "later spread wins over an earlier one" do
      node =
        {:element, "div", [{:spread, {%{id: "my_value_1"}}}, {:spread, {%{id: "my_value_2"}}}],
         []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_value_2"></div>), %{}, @server}
    end

    # Attribute order carries no meaning in HTML, so the winning entry simply stays where it is.
    test "overridden name is rendered at the position of the winning entry" do
      node =
        {:element, "div",
         [
           {"id", [text: "my_value_1"]},
           {"class", [text: "my_class"]},
           {:spread, {%{id: "my_value_2"}}}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div class="my_class" id="my_value_2"></div>), %{}, @server}
    end

    test "interleaved with named attributes" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "my_value_1"]},
           {:spread, {%{attr_2: "my_value_2"}}},
           {"attr_3", [expression: {"my_value_3"}]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div attr_1="my_value_1" attr-2="my_value_2" attr_3="my_value_3"></div>), %{},
                @server}
    end

    test "event attributes are filtered out, same as without a spread" do
      node =
        {:element, "div",
         [
           {"$click", [expression: {:my_command}]},
           {:spread, {%{id: "my_id"}}},
           {"$key_down", [expression: {:my_command}], %{key: [["enter"]]}}
         ], []}

      assert render_dom(node, @env, @server) == {~s(<div id="my_id"></div>), %{}, @server}
    end

    test "raises for a nil value" do
      node = {:element, "div", [{:spread, {nil}}], []}

      assert_raise ArgumentError,
                   "spread value must be a map or a keyword list, got: nil",
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a string value" do
      node = {:element, "div", [{:spread, {"my_string"}}], []}

      assert_raise ArgumentError,
                   ~s(spread value must be a map or a keyword list, got: "my_string"),
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a list which is not a keyword list" do
      node = {:element, "div", [{:spread, {[1, 2, 3]}}], []}

      assert_raise ArgumentError,
                   "spread value must be a map or a keyword list, got: [1, 2, 3]",
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a struct value" do
      node = {:element, "div", [{:spread, {~D[2024-01-15]}}], []}

      assert_raise ArgumentError,
                   "spread value must be a map or a keyword list, got: ~D[2024-01-15]",
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a '$'-prefixed atom key" do
      node = {:element, "div", [{:spread, {%{"$click": :my_command}}}], []}

      assert_raise ArgumentError,
                   ~s(event bindings can't be set through a spread, got the "$click" key),
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a '$'-prefixed string key" do
      node = {:element, "div", [{:spread, {%{"$click" => :my_command}}}], []}

      assert_raise ArgumentError,
                   ~s(event bindings can't be set through a spread, got the "$click" key),
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a '$'-prefixed nested key" do
      node = {:element, "div", [{:spread, {%{data: %{"$click" => :my_command}}}}], []}

      assert_raise ArgumentError,
                   ~s(event bindings can't be set through a spread, got the "$click" key),
                   fn -> render_dom(node, @env, @server) end
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

    test "required prop given" do
      node = {:component, Module89, [{"aaa", [text: "my_value"]}], []}

      assert render_dom(node, @env, @server) == {"prop_aaa = my_value", %{}, @server}
    end

    test "required prop missing" do
      node = {:component, Module89, [], []}

      expected_msg =
        ~s/component "Hologram.Test.Fixtures.Template.Renderer.Module89" is missing required prop "aaa"/

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "required prop missing, rendered from a parent template" do
      node = {:component, Module89, [], []}
      env = %Renderer.Env{parent_module: Module64}

      expected_msg =
        ~s/component "Hologram.Test.Fixtures.Template.Renderer.Module89" is missing required prop "aaa", / <>
          ~s/rendered from "Hologram.Test.Fixtures.Template.Renderer.Module64"/

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, env, @server)
      end
    end

    test "required prop declared to take value from context, value in context" do
      node = {:component, Module90, [], []}
      env = %Renderer.Env{context: %{my_context_key: "my_value"}}

      assert render_dom(node, env, @server) == {"prop_aaa = my_value", %{}, @server}
    end

    test "required prop declared to take value from context, value not in context" do
      node = {:component, Module90, [], []}

      expected_msg =
        ~s/component "Hologram.Test.Fixtures.Template.Renderer.Module90" is missing required prop "aaa"/

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "prop value in the :values list" do
      node = {:component, Module91, [{"aaa", [expression: {:small}]}], []}

      assert render_dom(node, @env, @server) == {"component vars = %{aaa: :small}", %{}, @server}
    end

    # A value written in a template is rejected by the compiler, so what reaches this check comes
    # from a spread or from context.
    test "prop value not in the :values list, arriving through a spread" do
      node = {:component, Module91, [{:spread, {%{aaa: :huge}}}], []}

      expected_msg =
        ~s/prop "aaa" of component "Hologram.Test.Fixtures.Template.Renderer.Module91" / <>
          "must be one of [:small, :large], got: :huge"

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "prop value not in the :values list names the template it was rendered from" do
      node = {:component, Module91, [{:spread, {%{aaa: :huge}}}], []}
      env = %Renderer.Env{parent_module: Module64}

      expected_msg =
        ~s/prop "aaa" of component "Hologram.Test.Fixtures.Template.Renderer.Module91" / <>
          "must be one of [:small, :large], got: :huge, " <>
          ~s/rendered from "Hologram.Test.Fixtures.Template.Renderer.Module64"/

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, env, @server)
      end
    end

    test "prop value from context not in the :values list" do
      node = {:component, Module92, [], []}
      env = %Renderer.Env{context: %{my_context_key: :huge}}

      expected_msg =
        ~s/prop "aaa" of component "Hologram.Test.Fixtures.Template.Renderer.Module92" / <>
          "must be one of [:small, :large], got: :huge"

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, env, @server)
      end
    end

    test "absent prop with a :values list doesn't raise" do
      node = {:component, Module91, [], []}

      assert render_dom(node, @env, @server) == {"component vars = %{}", %{}, @server}
    end
  end

  describe "component prop spread" do
    test "map value" do
      node = {:component, Module16, [{:spread, {%{prop_1: "my_value_1", prop_2: 2}}}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_1&quot;, prop_2: 2}', _registry,
              _server_struct} = render_dom(node, @env, @server)
    end

    test "keyword list value" do
      node = {:component, Module16, [{:spread, {[prop_1: "my_value_1", prop_2: 2]}}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_1&quot;, prop_2: 2}', _registry,
              _server_struct} = render_dom(node, @env, @server)
    end

    test "string keys" do
      node = {:component, Module16, [{:spread, {%{"prop_1" => "my_value_1"}}}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_1&quot;}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    # Prop names live in the Elixir namespace, so they are not dasherized the way attributes are.
    test "underscores in names are kept verbatim" do
      node = {:component, Module86, [{:spread, {%{my_prop_1: "my_value_1"}}}], []}

      assert {~s'component vars = %{my_prop_1: &quot;my_value_1&quot;}', _registry,
              _server_struct} =
               render_dom(node, @env, @server)
    end

    test "undeclared keys are filtered out" do
      node =
        {:component, Module16, [{:spread, {%{prop_1: "my_value_1", undeclared: "my_value_2"}}}],
         []}

      assert {~s'component vars = %{prop_1: &quot;my_value_1&quot;}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "values are passed as raw terms" do
      node = {:component, Module64, [{:spread, {%{my_prop: {1, 2, 3}}}}], []}

      assert render_dom(node, @env, @server) == {"my_prop = {1, 2, 3}", %{}, @server}
    end

    # Unlike the element branch, a map value doesn't recurse into composed names.
    test "map value of an entry is a raw prop value" do
      node = {:component, Module86, [{:spread, {%{my_prop_2: %{my_nested_key: 1}}}}], []}

      assert {~s'component vars = %{my_prop_2: %{my_nested_key: 1}}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "keyword list value of an entry is a raw prop value" do
      node = {:component, Module86, [{:spread, {%{my_prop_3: [my_nested_key: 1]}}}], []}

      assert {~s'component vars = %{my_prop_3: [my_nested_key: 1]}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "nil value is passed as-is" do
      node = {:component, Module86, [{:spread, {%{my_prop_1: nil}}}], []}

      assert {"component vars = %{my_prop_1: nil}", _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "false value is passed as-is" do
      node = {:component, Module86, [{:spread, {%{my_prop_1: false}}}], []}

      assert {"component vars = %{my_prop_1: false}", _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "named prop before the spread is overridden" do
      node =
        {:component, Module16,
         [{"prop_1", [text: "my_value_1"]}, {:spread, {%{prop_1: "my_value_2"}}}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_2&quot;}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "named prop after the spread wins" do
      node =
        {:component, Module16,
         [{:spread, {%{prop_1: "my_value_1"}}}, {"prop_1", [text: "my_value_2"]}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_2&quot;}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "later spread wins over an earlier one" do
      node =
        {:component, Module16,
         [{:spread, {%{prop_1: "my_value_1"}}}, {:spread, {%{prop_1: "my_value_2"}}}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_2&quot;}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "cid supplied through a spread initializes a stateful component" do
      node = {:component, Module16, [{:spread, {%{cid: "my_component", prop_1: "my_value"}}}], []}

      assert {~s'component vars = %{cid: &quot;my_component&quot;, prop_1: &quot;my_value&quot;}',
              %{"my_component" => %{module: Module16, struct: %Component{}}}, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "declared default value is applied for a key not supplied by the spread" do
      node = {:component, Module65, [{:spread, {%{prop_2: :my_value}}}], []}

      assert {~s'component vars = %{prop_1: &quot;abc&quot;, prop_2: :my_value, prop_3: 123}',
              _registry, _server_struct} = render_dom(node, @env, @server)
    end

    test "empty map value supplies no props" do
      node = {:component, Module16, [{"prop_1", [text: "my_value_1"]}, {:spread, {%{}}}], []}

      assert {~s'component vars = %{prop_1: &quot;my_value_1&quot;}', _registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "raises for a nil value" do
      node = {:component, Module16, [{:spread, {nil}}], []}

      assert_raise ArgumentError,
                   "spread value must be a map or a keyword list, got: nil",
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a string value" do
      node = {:component, Module16, [{:spread, {"my_string"}}], []}

      assert_raise ArgumentError,
                   ~s(spread value must be a map or a keyword list, got: "my_string"),
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a list which is not a keyword list" do
      node = {:component, Module16, [{:spread, {[1, 2, 3]}}], []}

      assert_raise ArgumentError,
                   "spread value must be a map or a keyword list, got: [1, 2, 3]",
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a struct value" do
      node = {:component, Module16, [{:spread, {~D[2024-01-15]}}], []}

      assert_raise ArgumentError,
                   "spread value must be a map or a keyword list, got: ~D[2024-01-15]",
                   fn -> render_dom(node, @env, @server) end
    end

    test "raises for a '$'-prefixed key" do
      node = {:component, Module16, [{:spread, {%{"$click" => :my_command}}}], []}

      assert_raise ArgumentError,
                   ~s(event bindings can't be set through a spread, got the "$click" key),
                   fn -> render_dom(node, @env, @server) end
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
                   ~r/^key :c not found in:\s+%\{.+\}$/s,
                   fn ->
                     render_dom(node, @env, @server)
                   end
    end

    test "framework sets server.cid to the component's cid during init/3" do
      node = {:component, Module79, [{"cid", [text: "my_component"]}], []}

      {_html, registry, _server} = render_dom(node, @env, @server)

      assert registry["my_component"].struct.state.observed_cid == "my_component"
    end
  end

  describe "default slot" do
    test "with single node" do
      node = {:component, Module8, [], [text: "123"]}
      assert render_dom(node, @env, @server) == {"abc123xyz", %{}, @server}
    end

    # Slot content belongs to the template that wrote it, not to the one holding the <slot />, so a
    # prop error in it must name the writer. The page/layout pair is the same case: a page's whole
    # template is its layout's slot content.
    test "a prop error in slot content names the template that wrote it" do
      node = {:component, Module8, [], [{:component, Module89, [], []}]}
      env = %Renderer.Env{parent_module: Module64}

      expected_msg =
        ~s/component "Hologram.Test.Fixtures.Template.Renderer.Module89" is missing required prop "aaa", / <>
          ~s/rendered from "Hologram.Test.Fixtures.Template.Renderer.Module64"/

      assert_raise Hologram.PropError, expected_msg, fn ->
        render_dom(node, env, @server)
      end
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

  describe "dynamic tag node, element branch" do
    test "without attributes or children" do
      # <{"div"}></{"div"}>
      node = {:dynamic_tag, {"div"}, [], []}

      assert render_dom(node, @env, @server) == {"<div></div>", %{}, @server}
    end

    test "with attributes" do
      node =
        {:dynamic_tag, {"div"},
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div attr_1="aaa" attr_2="123" attr_3="ccc987eee"></div>), %{}, @server}
    end

    test "with children" do
      node = {:dynamic_tag, {"div"}, [], [{:element, "span", [], [text: "abc"]}, {:text, "xyz"}]}

      assert render_dom(node, @env, @server) == {"<div><span>abc</span>xyz</div>", %{}, @server}
    end

    test "void element" do
      node = {:dynamic_tag, {"img"}, [{"attr_1", [text: "aaa"]}], []}

      assert render_dom(node, @env, @server) == {~s(<img attr_1="aaa" />), %{}, @server}
    end

    test "custom element" do
      node = {:dynamic_tag, {"my-widget"}, [], [{:text, "abc"}]}

      assert render_dom(node, @env, @server) == {"<my-widget>abc</my-widget>", %{}, @server}
    end

    test "filters out attributes that specify event handlers (starting with '$' character)" do
      node =
        {:dynamic_tag, {"div"},
         [
           {"attr_1", [text: "aaa"]},
           {"$attr_2", [text: "bbb"]},
           {"$attr_3", [text: "ccc"], ["mod_1"]}
         ], []}

      assert render_dom(node, @env, @server) == {~s(<div attr_1="aaa"></div>), %{}, @server}
    end

    test "cid attribute is rendered as a plain HTML attribute" do
      node = {:dynamic_tag, {"div"}, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div cid="my_component"></div>), %{}, @server}
    end

    test "with spread" do
      # <{"div"} ...{%{id: "my_id", class: "my_class"}}></{"div"}>
      node = {:dynamic_tag, {"div"}, [{:spread, {%{id: "my_id", class: "my_class"}}}], []}

      assert render_dom(node, @env, @server) ==
               {~s(<div class="my_class" id="my_id"></div>), %{}, @server}
    end

    test "with nested stateful component" do
      node =
        {:dynamic_tag, {"div"}, [], [{:component, Module3, [{"cid", [text: "component_3"]}], []}]}

      {html, component_registry, _server_struct} = render_dom(node, @env, @server)

      assert html == "<div><div>state_a = 1, state_b = 2</div></div>"

      assert component_registry == %{
               "component_3" => %{module: Module3, struct: %Component{state: %{a: 1, b: 2}}}
             }
    end

    test "tag name with uppercase chars" do
      # <{"DIV"}></{"DIV"}>
      node = {:dynamic_tag, {"DIV"}, [], []}

      assert render_dom(node, @env, @server) == {"<div></div>", %{}, @server}
    end

    test "SVG tag name that lost its case" do
      # <{"lineargradient"}></{"lineargradient"}>
      node = {:dynamic_tag, {"lineargradient"}, [], []}

      assert render_dom(node, @env, @server) ==
               {"<linearGradient></linearGradient>", %{}, @server}
    end

    test "SVG tag name that is already spelled the way the parser spells it" do
      # <{"linearGradient"}></{"linearGradient"}>
      node = {:dynamic_tag, {"linearGradient"}, [], []}

      assert render_dom(node, @env, @server) ==
               {"<linearGradient></linearGradient>", %{}, @server}
    end

    test "void element named with uppercase chars" do
      node = {:dynamic_tag, {"IMG"}, [{"attr_1", [text: "aaa"]}], []}

      assert render_dom(node, @env, @server) == {~s(<img attr_1="aaa" />), %{}, @server}
    end
  end

  describe "dynamic tag node, component branch" do
    test "stateless component without props" do
      # <{Module1} />
      node = {:dynamic_tag, {Module1}, [], []}

      assert render_dom(node, @env, @server) == {"<div>abc</div>", %{}, @server}
    end

    test "stateless component with props" do
      node =
        {:dynamic_tag, {Module2},
         [
           {"a", [text: "ddd"]},
           {"b", [expression: {222}]},
           {"c", [text: "fff", expression: {333}, text: "hhh"]}
         ], []}

      assert render_dom(node, @env, @server) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff333hhh</div>", %{}, @server}
    end

    test "stateful component" do
      node = {:dynamic_tag, {Module3}, [{"cid", [text: "my_component"]}], []}

      assert render_dom(node, @env, @server) ==
               {"<div>state_a = 1, state_b = 2</div>",
                %{"my_component" => %{module: Module3, struct: %Component{state: %{a: 1, b: 2}}}},
                %Server{
                  cookies: %{
                    "initial_cookie_key" => :initial_cookie_value,
                    "cookie_key_3" => :cookie_value_3
                  },
                  __meta__: %Metadata{
                    cookie_ops: %{
                      "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                      "cookie_key_3" => %Cookie{value: :cookie_value_3}
                    }
                  }
                }}
    end

    test "undeclared props are dropped" do
      node = {:dynamic_tag, {Module1}, [{"my_undeclared_prop", [text: "my_value"]}], []}

      assert render_dom(node, @env, @server) == {"<div>abc</div>", %{}, @server}
    end

    test "event attributes are not passed as props" do
      node = {:dynamic_tag, {Module2}, [{"$click", [text: "my_action"]}], []}

      expected_msg = build_key_error_msg(:a, %{})

      assert_raise KeyError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "with slot content" do
      node = {:dynamic_tag, {Module8}, [], [text: "123"]}

      assert render_dom(node, @env, @server) == {"abc123xyz", %{}, @server}
    end

    test "with prop spread" do
      node = {:dynamic_tag, {Module2}, [{:spread, {%{a: "ddd", b: 222, c: "fff"}}}], []}

      assert render_dom(node, @env, @server) ==
               {"<div>prop_a = ddd, prop_b = 222, prop_c = fff</div>", %{}, @server}
    end
  end

  describe "dynamic tag node, slots" do
    test "slot content is expanded through dynamic tag children" do
      node = {:component, Module87, [], [text: "abc"]}

      assert render_dom(node, @env, @server) ==
               {"87a,32a,87b,<div>abc</div>,87x,32z,87z", %{}, @server}
    end
  end

  describe "dynamic tag node, invalid tag name value" do
    test "non-component atom" do
      node = {:dynamic_tag, {:div}, [], []}

      expected_msg =
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: :div, which is not a component module"

      assert_raise ArgumentError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "page module" do
      node = {:dynamic_tag, {Module14}, [], []}

      expected_msg =
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: Hologram.Test.Fixtures.Template.Renderer.Module14, which is not a component module"

      assert_raise ArgumentError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "nil" do
      node = {:dynamic_tag, {nil}, [], []}

      expected_msg =
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: nil, which is not a component module"

      assert_raise ArgumentError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "integer" do
      node = {:dynamic_tag, {123}, [], []}

      expected_msg =
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: 123"

      assert_raise ArgumentError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "non-binary bitstring" do
      node = {:dynamic_tag, {<<3::2>>}, [], []}

      expected_msg =
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: <<3::size(2)>>"

      assert_raise ArgumentError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end

    test "map" do
      node = {:dynamic_tag, {%{a: 1}}, [], []}

      expected_msg =
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: %{a: 1}"

      assert_raise ArgumentError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end
  end

  describe "window node" do
    test "renders no markup" do
      node = {:element, "window", [{"$key_down", [text: "my_action"]}], []}

      assert render_dom(node, @env, @server) == {"", %{}, @server}
    end
  end

  describe "document node" do
    test "renders no markup" do
      node = {:element, "document", [{"$key_down", [text: "my_action"]}], []}

      assert render_dom(node, @env, @server) == {"", %{}, @server}
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

      assert render_page_without_tree(Module39, @params, @server, @opts) ==
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
                        {Hologram.Runtime, :instance_id} => @instance_id,
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

      assert render_page_without_tree(Module46, @params, @server, @opts) ==
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
                        {Hologram.Runtime, :instance_id} => @instance_id,
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

      assert render_page_without_tree(Module40, @params, @server, @opts) ==
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
                        {Hologram.Runtime, :instance_id} => @instance_id,
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

      assert render_page_without_tree(Module43, @params, @server, @opts) ==
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
                        {Hologram.Runtime, :instance_id} => @instance_id,
                        {Hologram.Runtime, :page_digest} => :dummy_module_43_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }, @server}
    end

    test "emitted in layout, accessed in component nested in layout" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module45, :dummy_module_45_digest)

      assert render_page_without_tree(Module45, @params, @server, @opts) ==
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
                        {Hologram.Runtime, :instance_id} => @instance_id,
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
               render_page_without_tree(Module14, @params, @server, @opts)
    end

    test "cast page param values to correct type" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module19, :dummy_module_19_digest)

      params = %{param_1: "abc", param_3: 123}

      assert {~s'page vars = %{param_1: &quot;abc&quot;, param_3: 123}', _component_registry,
              _server_struct} =
               render_page_without_tree(Module19, params, @server, @opts)
    end

    test "cast layout explicit static props" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module25, :dummy_module_25_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;prop_value_1&quot;, prop_3: &quot;prop_value_3&quot;}',
              _component_registry, _server_struct} =
               render_page_without_tree(Module25, @params, @server, @opts)
    end

    test "cast layout props passed implicitely from page state" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module27, :dummy_module_27_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;prop_value_1&quot;, prop_3: &quot;prop_value_3&quot;}',
              _component_registry, _server_struct} =
               render_page_without_tree(Module27, @params, @server, @opts)
    end

    test "aggregate page vars, giving state vars priority over param vars when there are name conflicts" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module21, :dummy_module_21_digest)

      params = %{key_1: "param_value_1", key_2: "param_value_2"}

      assert {~s'page vars = %{key_1: &quot;param_value_1&quot;, key_2: &quot;state_value_2&quot;, key_3: &quot;state_value_3&quot;}',
              _component_registry, _server_struct} =
               render_page_without_tree(Module21, params, @server, @opts)
    end

    test "aggregate layout vars, giving state vars priority over prop vars when there are name conflicts" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module24, :dummy_module_24_digest)

      assert {~s'layout vars = %{cid: &quot;layout&quot;, key_1: &quot;prop_value_1&quot;, key_2: &quot;state_value_2&quot;, key_3: &quot;state_value_3&quot;}',
              _component_registry, _server_struct} =
               render_page_without_tree(Module24, @params, @server, @opts)
    end

    test "merge the page component struct into the result" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      assert render_page_without_tree(Module28, @params, @server, @opts) ==
               {"",
                %{
                  "layout" => %{module: LayoutFixture, struct: %Component{}},
                  "page" => %{
                    module: Module28,
                    struct: %Component{
                      emitted_context: %{
                        {Hologram.Runtime, :csrf_token} => @csrf_token,
                        {Hologram.Runtime, :initial_page?} => false,
                        {Hologram.Runtime, :instance_id} => @instance_id,
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

      assert render_page_without_tree(Module29, @params, @server, @opts) ==
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
                        {Hologram.Runtime, :instance_id} => @instance_id,
                        {Hologram.Runtime, :page_digest} => :dummy_module_29_digest,
                        {Hologram.Runtime, :page_mounted?} => true
                      }
                    }
                  }
                }, @server}
    end

    test "passes server struct to layout and nested components and aggregates mutations" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module70, :dummy_module_70_digest)

      {_html, _component_registry, server_struct} =
        render_page_without_tree(Module70, @params, @server, @opts)

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

    test "accumulates broadcasts queued during init across the full page + layout + component tree" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module84, :dummy_module_84_digest)

      server = %{@server | cid: "page", instance_id: "test-instance-id"}

      {_html, _registry, returned_server} =
        render_page_without_tree(Module84, @params, server, @opts)

      # Render order: page init -> layout init -> comp_1 init -> comp_2 init
      # server.broadcasts is LIFO (head = most recent put_broadcast call):
      assert returned_server.broadcasts == [
               %Broadcast{
                 channel: {:instance, "test-instance-id"},
                 action_name: :component_broadcast,
                 params: %{text: "hi"}
               },
               %Broadcast{
                 channel: {:instance, "test-instance-id"},
                 action_name: :component_broadcast,
                 params: %{text: "hi"}
               },
               %Broadcast{
                 channel: {:instance, "test-instance-id"},
                 action_name: :layout_broadcast,
                 params: %{level: "layout"}
               },
               %Broadcast{
                 channel: {:instance, "test-instance-id"},
                 action_name: :page_broadcast,
                 params: %{level: "page"}
               }
             ]
    end

    test "injects (interpolated) asset manifest when the initial_page? opt is set to true" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module53, :dummy_module_53_digest)

      opts = [csrf_token: @csrf_token, initial_page?: true, instance_id: @instance_id]

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module53, @params, @server, opts)

      assert normalize_newlines(html) =~
               ~r'globalThis.Hologram.assetManifest = \{\n"hologram/runtime\.js": "/hologram/runtime\-1234567890abcdef\.js"[^\}]+\n\};'
    end

    test "doesn't inject asset manifest when the initial_page? opt is set to false" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module53, :dummy_module_53_digest)

      opts = [csrf_token: @csrf_token, initial_page?: false]

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module53, @params, @server, opts)

      refute String.contains?(html, "globalThis.Hologram.assetManifest")
    end

    test "interpolate component structs JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module48, @params, @server, @opts)

      expected =
        ~s/componentRegistry: Type.map([[Type.bitstring("layout"), Type.map([[Type.atom("module"), Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module49")], [Type.atom("struct"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")], [Type.atom("emitted_context"), Type.map([])], [Type.atom("next_action"), Type.atom("nil")], [Type.atom("next_command"), Type.atom("nil")], [Type.atom("next_page"), Type.atom("nil")], [Type.atom("state"), Type.map([])]])]])], [Type.bitstring("page"), Type.map([[Type.atom("module"), Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module48")], [Type.atom("struct"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component")], [Type.atom("emitted_context"), Type.map([[Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("csrf_token")]), Type.bitstring("#{@csrf_token}")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("initial_page?")]), Type.atom("false")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("instance_id")]), Type.bitstring("#{@instance_id}")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("page_digest")]), Type.bitstring("102790adb6c3b1956db310be523a7693")], [Type.tuple([Type.atom("Elixir.Hologram.Runtime"), Type.atom("page_mounted?")]), Type.atom("true")]])], [Type.atom("next_action"), Type.atom("nil")], [Type.atom("next_command"), Type.atom("nil")], [Type.atom("next_page"), Type.atom("nil")], [Type.atom("state"), Type.map([])]])]])]])/

      assert String.contains?(html, expected)
    end

    test "interpolate page module JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module48, @params, @server, @opts)

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
               render_page_without_tree(Module50, params, @server, @opts)

      expected =
        ~s/pageParams: Type.map([[Type.atom("key_1"), Type.integer(123n)], [Type.atom("key_2"), Type.bitstring("value_2")]])/

      assert String.contains?(html, expected)
    end

    test "does not interpolate self_echoes JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module48, @params, @server, @opts)

      assert String.contains?(html, "selfEchoes: $SELF_ECHOES_JS_PLACEHOLDER")
    end

    test "does not interpolate sub_receipt_adds JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module48, @params, @server, @opts)

      assert String.contains?(html, "subReceiptAdds: $SUB_RECEIPT_ADDS_JS_PLACEHOLDER")
    end

    test "does not interpolate sub_receipt_drops JS" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module48, @params, @server, @opts)

      assert String.contains?(html, "subReceiptDrops: $SUB_RECEIPT_DROPS_JS_PLACEHOLDER")
    end

    test "with DOCTYPE" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module62,
        "102790adb6c3b1956db310be523a7693"
      )

      assert {html, _component_registry, _server_struct} =
               render_page_without_tree(Module62, @params, @server, @opts)

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

      opts = [csrf_token: @csrf_token, initial_page?: true, instance_id: @instance_id]

      assert {_html, component_registry, _server_struct} =
               render_page_without_tree(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      assert page_emitted_context[{Hologram.Runtime, :csrf_token}] == @csrf_token
    end

    test "CSRF token is not put into page emitted context for subsequent page requests even when provided" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: @csrf_token, initial_page?: false]

      assert {_html, component_registry, _server_struct} =
               render_page_without_tree(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      refute Map.has_key?(page_emitted_context, {Hologram.Runtime, :csrf_token})
    end

    test "raises ArgumentError when CSRF token is not provided for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [initial_page?: true, instance_id: @instance_id]

      assert_raise ArgumentError, "CSRF token is required for initial page requests", fn ->
        render_page_without_tree(Module28, @params, @server, opts)
      end
    end

    test "raises ArgumentError when CSRF token is nil for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: nil, initial_page?: true, instance_id: @instance_id]

      assert_raise ArgumentError, "CSRF token is required for initial page requests", fn ->
        render_page_without_tree(Module28, @params, @server, opts)
      end
    end

    test "CSRF token is not required for subsequent page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [initial_page?: false]

      assert {_html, component_registry, _server_struct} =
               render_page_without_tree(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      refute Map.has_key?(page_emitted_context, {Hologram.Runtime, :csrf_token})
    end

    test "instance_id is put into page emitted context for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: @csrf_token, initial_page?: true, instance_id: @instance_id]

      assert {_html, component_registry, _server_struct} =
               render_page_without_tree(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      assert page_emitted_context[{Hologram.Runtime, :instance_id}] == @instance_id
    end

    test "instance_id is not put into page emitted context for subsequent page requests even when provided" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [initial_page?: false, instance_id: @instance_id]

      assert {_html, component_registry, _server_struct} =
               render_page_without_tree(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      refute Map.has_key?(page_emitted_context, {Hologram.Runtime, :instance_id})
    end

    test "raises ArgumentError when instance_id is not provided for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: @csrf_token, initial_page?: true]

      assert_raise ArgumentError, "instance_id is required for initial page requests", fn ->
        render_page_without_tree(Module28, @params, @server, opts)
      end
    end

    test "raises ArgumentError when instance_id is nil for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [csrf_token: @csrf_token, initial_page?: true, instance_id: nil]

      assert_raise ArgumentError, "instance_id is required for initial page requests", fn ->
        render_page_without_tree(Module28, @params, @server, opts)
      end
    end

    test "instance_id is not required for subsequent page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module28, :dummy_module_28_digest)

      opts = [initial_page?: false]

      assert {_html, component_registry, _server_struct} =
               render_page_without_tree(Module28, @params, @server, opts)

      page_emitted_context = component_registry["page"].struct.emitted_context

      refute Map.has_key?(page_emitted_context, {Hologram.Runtime, :instance_id})
    end

    test "framework sets server.cid to \"layout\" during layout init/3" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module80, :dummy_module_80_digest)

      {_html, registry, _server} = render_page_without_tree(Module80, @params, @server, @opts)

      assert registry["layout"].struct.state.observed_cid == "layout"
    end

    test "returns the tree the HTML is printed from, once the mount data is put back" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      %{html: html, mount_data: mount_data, tree: tree} =
        render_page(Module48, @params, @server, @opts)

      # The two projections are the same render. They differ only in that the HTML has the mount
      # data inlined, so putting it back into the printed tree must reproduce the HTML exactly.
      printed =
        tree
        |> print_dom()
        |> String.replace("$ASSET_MANIFEST_JS_PLACEHOLDER", mount_data.asset_manifest)
        |> String.replace("$COMPONENT_REGISTRY_JS_PLACEHOLDER", mount_data.component_registry)
        |> String.replace("$PAGE_MODULE_JS_PLACEHOLDER", mount_data.page_module)
        |> String.replace("$PAGE_PARAMS_JS_PLACEHOLDER", mount_data.page_params)

      assert printed == html
    end

    test "leaves every placeholder in the tree's scripts, mount data included" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      %{tree: tree} = render_page(Module48, @params, @server, @opts)

      script_text =
        tree
        |> collect_script_texts()
        |> Enum.join()

      assert String.contains?(script_text, "$ASSET_MANIFEST_JS_PLACEHOLDER")
      assert String.contains?(script_text, "$COMPONENT_REGISTRY_JS_PLACEHOLDER")
      assert String.contains?(script_text, "$PAGE_MODULE_JS_PLACEHOLDER")
      assert String.contains?(script_text, "$PAGE_PARAMS_JS_PLACEHOLDER")
      assert String.contains?(script_text, "selfEchoes: $SELF_ECHOES_JS_PLACEHOLDER")

      refute String.contains?(
               script_text,
               ~s/Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module48")/
             )
    end

    test "returns the mount data the HTML projection interpolates" do
      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module48,
        "102790adb6c3b1956db310be523a7693"
      )

      %{html: html, mount_data: mount_data} = render_page(Module48, @params, @server, @opts)

      assert mount_data.page_module ==
               ~s/Type.atom("Elixir.Hologram.Test.Fixtures.Template.Renderer.Module48")/

      assert mount_data.page_params == "Type.map([])"
      assert String.starts_with?(mount_data.component_registry, "Type.map([")

      # Each value is what the HTML carries, which is what makes it safe to send beside the tree
      # instead of inside it.
      for value <- Map.values(mount_data) do
        assert String.contains?(html, value)
      end
    end
  end

  # IMPORTANT!
  # Keep client-side Renderer "escaping" and server-side Renderer "escaping" unit tests consistent.
  #
  # Note: the behaviour is different on client-side vs server-side
  # because client-side escaping is delegated to Snabbdom
  describe "escaping" do
    test "text inside non-raw-text elements" do
      # <div>abc < xyz</div>
      node = {:element, "div", [], [text: "abc < xyz"]}

      assert render_dom(node, @env, @server) == {"<div>abc &lt; xyz</div>", %{}, @server}
    end

    test "text inside script elements" do
      # <script>abc < xyz</script>
      node = {:element, "script", [], [text: "abc < xyz"]}

      assert render_dom(node, @env, @server) == {"<script>abc < xyz</script>", %{}, @server}
    end

    test "text inside style elements" do
      # <style>a > b & c</style>
      node = {:element, "style", [], [text: "a > b & c"]}

      assert render_dom(node, @env, @server) == {"<style>a > b & c</style>", %{}, @server}
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

    test "expression inside non-raw-text elements" do
      # <div>{"abc < xyz"}</div>
      node = {:element, "div", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env, @server) == {"<div>abc &lt; xyz</div>", %{}, @server}
    end

    test "expression inside script elements" do
      # <script>{"abc < xyz"}</script>
      node = {:element, "script", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env, @server) ==
               {"<script>abc \\u{3C} xyz</script>", %{}, @server}
    end

    test "expression inside style elements" do
      # <style>{"abc < xyz"}</style>
      node = {:element, "style", [], [expression: {"abc < xyz"}]}

      assert render_dom(node, @env, @server) ==
               {"<style>abc \\00003C  xyz</style>", %{}, @server}
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

    test "text inside component prop" do
      # <Module64 my_prop="abc < xyz" />
      node = {:component, Module64, [{"my_prop", [text: "abc < xyz"]}], []}

      assert render_dom(node, @env, @server) ==
               {~s'my_prop = &quot;abc &lt; xyz&quot;', %{}, @server}
    end

    test "expression inside component prop" do
      # <Module64 my_prop={"abc < xyz"} />
      node = {:component, Module64, [{"my_prop", [expression: {"abc < xyz"}]}], []}

      assert render_dom(node, @env, @server) ==
               {~s'my_prop = &quot;abc &lt; xyz&quot;', %{}, @server}
    end

    test "multi-part component prop" do
      # <Module64 my_prop="a < b {"< c <"} d < e" />
      node =
        {:component, Module64,
         [{"my_prop", [text: "a < b ", expression: {"< c <"}, text: " d < e"]}], []}

      assert render_dom(node, @env, @server) ==
               {~s'my_prop = &quot;a &lt; b &lt; c &lt; d &lt; e&quot;', %{}, @server}
    end
  end

  describe "stringify_for_script_interpolation/1" do
    test "atom, non-boolean and non-nil" do
      assert stringify_for_script_interpolation(:abc) == "abc"
    end

    test "atom, true" do
      assert stringify_for_script_interpolation(true) == "true"
    end

    test "atom, false" do
      assert stringify_for_script_interpolation(false) == "false"
    end

    test "atom, nil" do
      assert stringify_for_script_interpolation(nil) == ""
    end

    test "bitstring, binary" do
      assert stringify_for_script_interpolation(<<97, 98, 99>>) == "abc"
    end

    test "bitstring, non-binary" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(<<97::6, 98::4>>)
                   end
    end

    test "float" do
      assert stringify_for_script_interpolation(1.23) == "1.23"
    end

    test "function, anonymous" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(fn x, y -> x + y end)
                   end
    end

    test "function, captured" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(&Map.put/3)
                   end
    end

    test "integer" do
      assert stringify_for_script_interpolation(123) == "123"
    end

    test "list, strings" do
      assert stringify_for_script_interpolation(["ab", "cd"]) == "abcd"
    end

    test "list, Unicode code points" do
      assert stringify_for_script_interpolation([97, 98, 99]) == "abc"
    end

    test "list, not stringifiable" do
      assert_error ArgumentError, ~r/cannot convert the given list to a string/, fn ->
        stringify_for_script_interpolation([1, nil, 2])
      end
    end

    test "map, atom keys" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(%{a: 1, b: 2})
                   end
    end

    test "map, mixed keys" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(%{:a => 1, "b" => nil, 2 => 3})
                   end
    end

    test "PID" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(pid("0.11.222"))
                   end
    end

    test "port" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(port("0.11"))
                   end
    end

    test "reference" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(ref("0.1.2.3"))
                   end
    end

    test "struct, having String.Chars protocol implementation" do
      value = %Version{major: 1, minor: 2, patch: 3}

      assert stringify_for_script_interpolation(value) == "1.2.3"
    end

    test "struct, not having String.Chars protocol implementation" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation(MapSet.new([1, 2, 3]))
                   end
    end

    test "tuple" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_script_interpolation({97, 98, 99})
                   end
    end

    test "backslash char" do
      assert stringify_for_script_interpolation("\\") == "\\\\"
    end

    test "double quote char" do
      assert stringify_for_script_interpolation("\"") == "\\\""
    end

    test "single quote char" do
      assert stringify_for_script_interpolation("'") == "\\'"
    end

    test "backtick char" do
      assert stringify_for_script_interpolation("`") == "\\`"
    end

    test "dollar char" do
      assert stringify_for_script_interpolation("$") == "\\$"
    end

    test "line feed char" do
      assert stringify_for_script_interpolation("\n") == "\\n"
    end

    test "carriage return char" do
      assert stringify_for_script_interpolation("\r") == "\\r"
    end

    test "null char" do
      assert stringify_for_script_interpolation(<<0>>) == "\\u{0}"
    end

    test "less-than char" do
      assert stringify_for_script_interpolation("<") == "\\u{3C}"
    end

    test "closing script tag" do
      # An unescaped "<" would end the script element the value is written into.
      assert stringify_for_script_interpolation("</script>") == "\\u{3C}/script>"
    end

    test "template literal expression opener" do
      # Inside a template literal an unescaped "${" would run what follows it as code.
      assert stringify_for_script_interpolation("${x}") == "\\${x}"
    end

    test "greater-than and ampersand chars travel as themselves" do
      assert stringify_for_script_interpolation("a > b & c") == "a > b & c"
    end

    test "non-ASCII text travels as itself" do
      assert stringify_for_script_interpolation("全息图") == "全息图"
    end

    test "text around escaped chars is kept" do
      assert stringify_for_script_interpolation(~s(say "hi" <b>)) == ~S(say \"hi\" \u{3C}b>)
    end
  end

  describe "stringify_for_style_interpolation/1" do
    test "atom, non-boolean and non-nil" do
      assert stringify_for_style_interpolation(:abc) == "abc"
    end

    test "atom, true" do
      assert stringify_for_style_interpolation(true) == "true"
    end

    test "atom, false" do
      assert stringify_for_style_interpolation(false) == "false"
    end

    test "atom, nil" do
      assert stringify_for_style_interpolation(nil) == ""
    end

    test "bitstring, binary" do
      assert stringify_for_style_interpolation(<<97, 98, 99>>) == "abc"
    end

    test "bitstring, non-binary" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(<<97::6, 98::4>>)
                   end
    end

    test "float" do
      assert stringify_for_style_interpolation(1.23) == "1.23"
    end

    test "function, anonymous" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(fn x, y -> x + y end)
                   end
    end

    test "function, captured" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(&Map.put/3)
                   end
    end

    test "integer" do
      assert stringify_for_style_interpolation(123) == "123"
    end

    test "list, strings" do
      assert stringify_for_style_interpolation(["ab", "cd"]) == "abcd"
    end

    test "list, Unicode code points" do
      assert stringify_for_style_interpolation([97, 98, 99]) == "abc"
    end

    test "list, not stringifiable" do
      assert_error ArgumentError, ~r/cannot convert the given list to a string/, fn ->
        stringify_for_style_interpolation([1, nil, 2])
      end
    end

    test "map, atom keys" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(%{a: 1, b: 2})
                   end
    end

    test "map, mixed keys" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(%{:a => 1, "b" => nil, 2 => 3})
                   end
    end

    test "PID" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(pid("0.11.222"))
                   end
    end

    test "port" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(port("0.11"))
                   end
    end

    test "reference" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(ref("0.1.2.3"))
                   end
    end

    test "struct, having String.Chars protocol implementation" do
      value = %Version{major: 1, minor: 2, patch: 3}

      assert stringify_for_style_interpolation(value) == "1.2.3"
    end

    test "struct, not having String.Chars protocol implementation" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation(MapSet.new([1, 2, 3]))
                   end
    end

    test "tuple" do
      assert_error Protocol.UndefinedError,
                   ~r/protocol String.Chars not implemented for/,
                   fn ->
                     stringify_for_style_interpolation({97, 98, 99})
                   end
    end

    test "backslash char" do
      assert stringify_for_style_interpolation("\\") == "\\\\"
    end

    test "double quote char" do
      assert stringify_for_style_interpolation("\"") == "\\\""
    end

    test "single quote char" do
      assert stringify_for_style_interpolation("'") == "\\'"
    end

    test "line feed char" do
      assert stringify_for_style_interpolation("\n") == "\\00000A "
    end

    test "carriage return char" do
      assert stringify_for_style_interpolation("\r") == "\\00000D "
    end

    test "form feed char" do
      # CSS preprocessing folds a form feed into a newline, which a string literal can't hold.
      assert stringify_for_style_interpolation("\f") == "\\00000C "
    end

    test "null char" do
      assert stringify_for_style_interpolation(<<0>>) == "\\00FFFD "
    end

    test "less-than char" do
      assert stringify_for_style_interpolation("<") == "\\00003C "
    end

    test "closing style tag" do
      # An unescaped "<" would end the style element the value is written into.
      assert stringify_for_style_interpolation("</style>") == "\\00003C /style>"
    end

    test "backtick and dollar chars travel as themselves" do
      assert stringify_for_style_interpolation("`${x}") == "`${x}"
    end

    test "greater-than and ampersand chars travel as themselves" do
      # A child combinator in an interpolated selector is the point of the issue this covers.
      assert stringify_for_style_interpolation("a > b & c") == "a > b & c"
    end

    test "space after an escaped char is kept" do
      # The escape carries a space of its own, which the CSS tokenizer eats instead of this one.
      assert stringify_for_style_interpolation("a< b") == "a\\00003C  b"
    end

    test "hex digit after an escaped char is not absorbed" do
      assert stringify_for_style_interpolation("<a") == "\\00003C a"
    end

    test "non-ASCII text travels as itself" do
      assert stringify_for_style_interpolation("全息图") == "全息图"
    end

    test "text around escaped chars is kept" do
      assert stringify_for_style_interpolation(~s(say "hi" <b>)) == ~S(say \"hi\" \00003C b>)
    end
  end

  describe "encode_tree/1" do
    test "text node" do
      tree = {:text, "abc < xyz"}

      assert encode_tree(tree) == ["abc < xyz"]
    end

    test "doctype node" do
      tree = {:doctype, "html"}

      assert encode_tree(tree) == [["d", "html"]]
    end

    test "element node, without attributes or children" do
      tree = {:element, "div", [], []}

      assert encode_tree(tree) == [["div", [], []]]
    end

    test "element node, with attribute" do
      # <div class="big"></div>
      tree = {:element, "div", [{"class", [text: "big"]}], []}

      assert encode_tree(tree) == [["div", ["class", "big"], []]]
    end

    test "element node, with boolean attribute" do
      # <input disabled />
      tree = {:element, "input", [{"disabled", []}], []}

      assert encode_tree(tree) == [["input", ["disabled", nil], []]]
    end

    test "element node, with multiple attributes" do
      # <div class="big" hidden id="abc"></div>
      tree =
        {:element, "div", [{"class", [text: "big"]}, {"hidden", []}, {"id", [text: "abc"]}], []}

      assert encode_tree(tree) == [["div", ["class", "big", "hidden", nil, "id", "abc"], []]]
    end

    test "element node, with element key" do
      # The $key attribute travels, unlike in the HTML projection: it is what carries element
      # identity across a navigation.
      tree = {:element, "div", [{"$key", [text: "k1:0"]}], []}

      assert encode_tree(tree) == [["div", ["$key", "k1:0"], []]]
    end

    test "element node, with children" do
      # <div>abc<span></span></div>
      tree = {:element, "div", [], [{:text, "abc"}, {:element, "span", [], []}]}

      assert encode_tree(tree) == [["div", [], ["abc", ["span", [], []]]]]
    end

    test "element node, nested" do
      # <div><span><b>abc</b></span></div>
      tree =
        {:element, "div", [], [{:element, "span", [], [{:element, "b", [], [{:text, "abc"}]}]}]}

      assert encode_tree(tree) == [["div", [], [["span", [], [["b", [], ["abc"]]]]]]]
    end

    test "element node, void with children" do
      # A void element keeps the children the tree gave it, unlike in the HTML projection.
      tree = {:element, "br", [], [{:text, "abc"}]}

      assert encode_tree(tree) == [["br", [], ["abc"]]]
    end

    test "public comment node" do
      # <!--abc-->
      tree = {:public_comment, [{:text, "abc"}]}

      assert encode_tree(tree) == [["c", ["abc"]]]
    end

    test "public comment node, with multiple children" do
      # <!--abc<div></div>-->
      tree = {:public_comment, [{:text, "abc"}, {:element, "div", [], []}]}

      assert encode_tree(tree) == [["c", ["abc", ["div", [], []]]]]
    end

    test "node list" do
      tree = [{:text, "abc"}, {:element, "div", [], []}, {:doctype, "html"}]

      assert encode_tree(tree) == ["abc", ["div", [], []], ["d", "html"]]
    end

    test "empty node list" do
      assert encode_tree([]) == []
    end

    test "single node is wrapped in a list" do
      # The result is always a list, so the client never has to tell a node apart from a list.
      assert encode_tree({:text, "abc"}) == ["abc"]
    end

    test "nil tree" do
      # A <window> or <document> tag renders to no node at all.
      assert encode_tree(nil) == []
    end

    test "result survives JSON encoding" do
      tree = [
        {:doctype, "html"},
        {:element, "div", [{"class", [text: "big"]}, {"hidden", []}],
         [{:text, "abc"}, {:public_comment, [{:text, " x "}]}]}
      ]

      encoded =
        tree
        |> encode_tree()
        |> JSON.encode!()

      assert encoded ==
               ~s([["d","html"],["div",["class","big","hidden",null],["abc",["c",[" x "]]]]])
    end
  end

  describe "interpolate_self_echoes_js/2" do
    test "substitutes the placeholder with the encoded list of actions" do
      html = ~s'before selfEchoes: $SELF_ECHOES_JS_PLACEHOLDER after'

      actions = [
        %Hologram.Component.Action{
          name: :my_action,
          params: %{text: "hi"},
          target: "page"
        }
      ]

      result = Renderer.interpolate_self_echoes_js(html, actions)

      assert result ==
               ~s'before selfEchoes: Type.list([Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action")], [Type.atom("params"), Type.map([[Type.atom("text"), Type.bitstring("hi")]])], [Type.atom("target"), Type.bitstring("page")]])]) after'
    end

    test "substitutes the placeholder with an empty list when no actions are provided" do
      html = ~s'before selfEchoes: $SELF_ECHOES_JS_PLACEHOLDER after'

      result = Renderer.interpolate_self_echoes_js(html, [])

      assert result == ~s'before selfEchoes: Type.list([]) after'
    end
  end

  describe "interpolate_sub_receipt_adds_js/2" do
    test "substitutes the placeholder with the encoded list of subscription receipts" do
      html = ~s'before subReceiptAdds: $SUB_RECEIPT_ADDS_JS_PLACEHOLDER after'

      sub_receipt_adds = [{:room_a, "page", "signed-token"}]

      result = Renderer.interpolate_sub_receipt_adds_js(html, sub_receipt_adds)

      assert result ==
               ~s'before subReceiptAdds: Type.list([Type.tuple([Type.atom("room_a"), Type.bitstring("page"), Type.bitstring("signed-token")])]) after'
    end

    test "substitutes the placeholder with an empty list when no receipts are provided" do
      html = ~s'before subReceiptAdds: $SUB_RECEIPT_ADDS_JS_PLACEHOLDER after'

      result = Renderer.interpolate_sub_receipt_adds_js(html, [])

      assert result == ~s'before subReceiptAdds: Type.list([]) after'
    end
  end

  describe "interpolate_sub_receipt_drops_js/2" do
    test "substitutes the placeholder with the encoded list of subscription drops" do
      html = ~s'before subReceiptDrops: $SUB_RECEIPT_DROPS_JS_PLACEHOLDER after'

      sub_receipt_drops = [{:room_a, "page"}]

      result = Renderer.interpolate_sub_receipt_drops_js(html, sub_receipt_drops)

      assert result ==
               ~s'before subReceiptDrops: Type.list([Type.tuple([Type.atom("room_a"), Type.bitstring("page")])]) after'
    end

    test "substitutes the placeholder with an empty list when no drops are provided" do
      html = ~s'before subReceiptDrops: $SUB_RECEIPT_DROPS_JS_PLACEHOLDER after'

      result = Renderer.interpolate_sub_receipt_drops_js(html, [])

      assert result == ~s'before subReceiptDrops: Type.list([]) after'
    end
  end

  describe "print_dom/1" do
    test "text node" do
      dom = {:text, "abc < xyz"}

      assert print_dom(dom) == "abc &lt; xyz"
    end

    test "text node, inside script element" do
      # <script>abc < xyz</script>
      dom = {:element, "script", [], [{:text, "abc < xyz"}]}

      assert print_dom(dom) == "<script>abc < xyz</script>"
    end

    test "text node, inside style element" do
      # <style>a > b & c</style>
      dom = {:element, "style", [], [{:text, "a > b & c"}]}

      assert print_dom(dom) == "<style>a > b & c</style>"
    end

    test "doctype node" do
      dom = {:doctype, "html"}

      assert print_dom(dom) == "<!DOCTYPE html>"
    end

    test "element node, without attributes or children" do
      dom = {:element, "div", [], []}

      assert print_dom(dom) == "<div></div>"
    end

    test "element node, with children" do
      # <div>abc<span></span></div>
      dom = {:element, "div", [], [{:text, "abc"}, {:element, "span", [], []}]}

      assert print_dom(dom) == "<div>abc<span></span></div>"
    end

    test "element node, nested" do
      # <div><span><b>abc</b></span></div>
      dom =
        {:element, "div", [], [{:element, "span", [], [{:element, "b", [], [{:text, "abc"}]}]}]}

      assert print_dom(dom) == "<div><span><b>abc</b></span></div>"
    end

    test "element node, void" do
      # <img src="abc.jpg" />
      dom = {:element, "img", [{"src", [text: "abc.jpg"]}], []}

      assert print_dom(dom) == ~s(<img src="abc.jpg" />)
    end

    test "element node, void with children" do
      # A void element renders no children, whatever it was given.
      dom = {:element, "br", [], [{:text, "abc"}]}

      assert print_dom(dom) == "<br />"
    end

    test "public comment node" do
      # <!--abc < xyz<div></div>-->
      dom = {:public_comment, [{:text, "abc < xyz"}, {:element, "div", [], []}]}

      assert print_dom(dom) == "<!--abc &lt; xyz<div></div>-->"
    end

    test "public comment node, inside script element" do
      # <script><!--abc < xyz--></script>
      dom = {:element, "script", [], [{:public_comment, [{:text, "abc < xyz"}]}]}

      assert print_dom(dom) == "<script><!--abc < xyz--></script>"
    end

    test "node list" do
      dom = [{:text, "abc"}, {:element, "div", [], []}, {:text, "xyz"}]

      assert print_dom(dom) == "abc<div></div>xyz"
    end

    test "attribute with a value" do
      dom = {:element, "div", [{"attr_1", [text: "aaa"]}, {"attr_2", [text: "bbb"]}], []}

      assert print_dom(dom) == ~s(<div attr_1="aaa" attr_2="bbb"></div>)
    end

    test "attribute with an empty value list" do
      dom = {:element, "input", [{"checked", []}], []}

      assert print_dom(dom) == "<input checked />"
    end

    test "attribute with an empty text value" do
      dom = {:element, "div", [{"class", [text: ""]}], []}

      assert print_dom(dom) == "<div class></div>"
    end

    test "attribute value is escaped" do
      dom = {:element, "div", [{"class", [text: "abc < xyz"]}], []}

      assert print_dom(dom) == ~s(<div class="abc &lt; xyz"></div>)
    end

    test "framework attributes are not printed" do
      dom =
        {:element, "div",
         [
           {"$key", [text: "a1b2c3:4"]},
           {"class", [text: "aaa"]},
           {"$click", [text: "my_action"]}
         ], []}

      assert print_dom(dom) == ~s(<div class="aaa"></div>)
    end

    test "element node, with only framework attributes" do
      dom = {:element, "div", [{"$key", [text: "a1b2c3:4"]}], []}

      assert print_dom(dom) == "<div></div>"
    end
  end

  describe "render_tree/3" do
    test "text node is held unescaped" do
      node = {:text, "abc < xyz"}

      assert render_tree(node, @env, @server) == {{:text, "abc < xyz"}, %{}, @server}
    end

    test "expression node evaluates to unescaped text" do
      # {"abc < xyz"}
      node = {:expression, {"abc < xyz"}}

      assert render_tree(node, @env, @server) == {{:text, "abc < xyz"}, %{}, @server}
    end

    test "expression node inside a script element evaluates to string literal text" do
      # <script>{"abc < xyz"}</script>
      node = {:element, "script", [], [expression: {"abc < xyz"}]}

      assert render_tree(node, @env, @server) ==
               {{:element, "script", [], [{:text, "abc \\u{3C} xyz"}]}, %{}, @server}
    end

    test "doctype node" do
      node = {:doctype, "html"}

      assert render_tree(node, @env, @server) == {{:doctype, "html"}, %{}, @server}
    end

    test "public comment node" do
      # <!--abc<div></div>-->
      node = {:public_comment, [{:text, "abc"}, {:element, "div", [], []}]}

      assert render_tree(node, @env, @server) ==
               {{:public_comment, [{:text, "abc"}, {:element, "div", [], []}]}, %{}, @server}
    end

    test "element node, attribute value parts collapse to a single unescaped string" do
      # <div attr="ccc{987} < eee"></div>
      node =
        {:element, "div", [{"attr", [text: "ccc", expression: {987}, text: " < eee"]}], []}

      assert render_tree(node, @env, @server) ==
               {{:element, "div", [{"attr", [text: "ccc987 < eee"]}], []}, %{}, @server}
    end

    test "component node, prop value parts collapse to a single unescaped string" do
      # <Module64 my_prop="ccc{987} < eee" />
      node =
        {:component, Module64, [{"my_prop", [text: "ccc", expression: {987}, text: " < eee"]}],
         []}

      assert render_tree(node, @env, @server) ==
               {[{:text, ~s'my_prop = "ccc987 < eee"'}], %{}, @server}
    end

    test "element node, attribute with an empty value list stays a boolean attribute" do
      # <input checked />
      node = {:element, "input", [{"checked", []}], []}

      assert render_tree(node, @env, @server) ==
               {{:element, "input", [{"checked", []}], []}, %{}, @server}
    end

    test "element node, attribute with a nil expression value is omitted" do
      # <div class={nil}></div>
      node = {:element, "div", [{"class", [expression: {nil}]}], []}

      assert render_tree(node, @env, @server) == {{:element, "div", [], []}, %{}, @server}
    end

    test "element node, attribute with a false expression value is omitted" do
      # <div hidden={false}></div>
      node = {:element, "div", [{"hidden", [expression: {false}]}], []}

      assert render_tree(node, @env, @server) == {{:element, "div", [], []}, %{}, @server}
    end

    test "element node, $key attribute is kept" do
      node = {:element, "div", [{"$key", [text: "a1b2c3:4"]}], []}

      assert render_tree(node, @env, @server) ==
               {{:element, "div", [{"$key", [text: "a1b2c3:4"]}], []}, %{}, @server}
    end

    test "element node, event attribute is dropped" do
      # <button $click="my_action">abc</button>
      node = {:element, "button", [{"$click", [text: "my_action"]}], [{:text, "abc"}]}

      assert render_tree(node, @env, @server) ==
               {{:element, "button", [], [{:text, "abc"}]}, %{}, @server}
    end

    test "element node, void element keeps its children in the tree" do
      node = {:element, "br", [], [{:text, "abc"}]}

      assert render_tree(node, @env, @server) ==
               {{:element, "br", [], [{:text, "abc"}]}, %{}, @server}
    end

    test "window node renders to nil" do
      node = {:element, "window", [], []}

      assert render_tree(node, @env, @server) == {nil, %{}, @server}
    end

    test "document node renders to nil" do
      node = {:element, "document", [], []}

      assert render_tree(node, @env, @server) == {nil, %{}, @server}
    end

    test "node list, nil nodes are filtered out" do
      # {%if false}abc{/if}xyz
      nodes = [nil, {:text, "xyz"}]

      assert render_tree(nodes, @env, @server) == {[{:text, "xyz"}], %{}, @server}
    end

    test "node list, adjacent text and expression nodes merge into one text node" do
      # aaa{123}zzz
      nodes = [{:text, "aaa"}, {:expression, {123}}, {:text, "zzz"}]

      assert render_tree(nodes, @env, @server) == {[{:text, "aaa123zzz"}], %{}, @server}
    end

    test "node list, text nodes separated by an element do not merge" do
      # aaa<br />zzz
      nodes = [{:text, "aaa"}, {:element, "br", [], []}, {:text, "zzz"}]

      assert render_tree(nodes, @env, @server) ==
               {[{:text, "aaa"}, {:element, "br", [], []}, {:text, "zzz"}], %{}, @server}
    end

    test "node list, text merges across a component boundary" do
      # aaa<Module88 />
      nodes = [{:text, "aaa"}, {:component, Module88, [], []}]

      assert render_tree(nodes, @env, @server) == {[{:text, "aaabbb"}], %{}, @server}
    end

    test "component node, rendered nodes are spliced into the enclosing list" do
      # aaa<Module1 />zzz
      nodes = [{:text, "aaa"}, {:component, Module1, [], []}, {:text, "zzz"}]

      assert render_tree(nodes, @env, @server) ==
               {[
                  {:text, "aaa"},
                  {:element, "div", [{"$key", [text: "kqd760:0"]}], [{:text, "abc"}]},
                  {:text, "zzz"}
                ], %{}, @server}
    end

    test "stateful component node, tree plus component registry plus mutated server struct" do
      # <Module3 cid="component_3" />
      node = {:component, Module3, [{"cid", [text: "component_3"]}], []}

      assert render_tree(node, @env, @server) ==
               {[
                  {:element, "div", [{"$key", [text: "w53jft:0"]}],
                   [{:text, "state_a = 1, state_b = 2"}]}
                ],
                %{
                  "component_3" => %{
                    module: Module3,
                    struct: %Component{
                      state: %{a: 1, b: 2}
                    }
                  }
                },
                %Server{
                  cookies: %{
                    "initial_cookie_key" => :initial_cookie_value,
                    "cookie_key_3" => :cookie_value_3
                  },
                  __meta__: %Metadata{
                    cookie_ops: %{
                      "initial_cookie_key" => %Cookie{value: :initial_cookie_value},
                      "cookie_key_3" => %Cookie{value: :cookie_value_3}
                    }
                  }
                }}
    end
  end

  defp collect_script_texts({:element, "script", _attrs, children}) do
    for {:text, text} <- children, do: text
  end

  defp collect_script_texts({:element, _tag_name, _attrs, children}) do
    collect_script_texts(children)
  end

  defp collect_script_texts(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_script_texts/1)
  end

  defp collect_script_texts(_node), do: []

  # The tree projection is covered by its own tests - these tests assert the projections the
  # pre-tree render returned, unchanged.
  defp render_page_without_tree(page_module, params, server_struct, opts) do
    %{component_registry: component_registry, html: html, server_struct: mutated_server_struct} =
      render_page(page_module, params, server_struct, opts)

    {html, component_registry, mutated_server_struct}
  end
end
