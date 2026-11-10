defmodule Hologram.Template.DOMTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.DOM

  alias Hologram.Compiler.AST
  alias Hologram.Template.Parser

  # The key an element carries for the place it holds in the given template, counted over the
  # elements in source order. Built the way the compiler builds it rather than written out, so that
  # editing a template in a test doesn't silently invalidate the hash - the hash itself is asserted
  # verbatim by the marker tests.
  defp key(tags, index) do
    {"$key", [text: "#{template_hash(tags)}:#{index}"]}
  end

  # The attributes a tag carries for its place in the template: one for an element, none for a
  # component, which renders the nodes of its own template rather than a node of its own.
  defp key_attrs(:element, tags, index), do: [key(tags, index)]

  defp key_attrs(_tag_type, _tags, _index), do: []

  # How far the keys of a tag's children are shifted by the tag itself: by one when it took a key,
  # by none when it didn't.
  defp key_offset(:element), do: 1

  defp key_offset(_tag_type), do: 0

  describe "build_ast/1, text node" do
    test "without double quotes" do
      assert build_ast([{:text, "abc"}]) == [{:text, "abc"}]
    end

    test "with double quotes" do
      assert build_ast([{:text, "aaa\"bbb\"ccc"}]) == [text: "aaa\"bbb\"ccc"]
    end

    test "with HTML entities" do
      assert build_ast([{:text, "Tom &amp; Jerry"}]) == [{:text, "Tom & Jerry"}]
    end

    test "escapes doubles quotes coming from &quot; HTML entity" do
      result = build_ast([{:text, "aaa &quot;bbb&quot; ccc"}])

      assert result == [{:text, ~s'aaa "bbb" ccc'}]
    end
  end

  describe "build_ast/1, public comment node" do
    test "empty" do
      # "<!---->"
      tags = [:public_comment_start, :public_comment_end]

      assert build_ast(tags) == [public_comment: []]
    end

    test "with text child" do
      # <!--abc-->
      tags = [:public_comment_start, {:text, "abc"}, :public_comment_end]

      assert build_ast(tags) == [public_comment: [{:text, "abc"}]]
    end

    test "with element child" do
      # <!--<div></div>-->
      tags = [
        :public_comment_start,
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        :public_comment_end
      ]

      assert build_ast(tags) == [
               public_comment: [{:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}]
             ]
    end

    test "with component child" do
      # <!--<MyComponent></MyComponent>-->
      tags = [
        :public_comment_start,
        {:start_tag, {"MyComponent", []}},
        {:end_tag, "MyComponent"},
        :public_comment_end
      ]

      assert build_ast(tags) == [
               public_comment: [
                 {:{}, [line: 1],
                  [
                    :component,
                    {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                    [],
                    []
                  ]}
               ]
             ]
    end

    test "with multiple children" do
      # <!--abc<div></div>-->
      tags = [
        :public_comment_start,
        {:text, "abc"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        :public_comment_end
      ]

      assert build_ast(tags) == [
               public_comment: [
                 {:text, "abc"},
                 {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}
               ]
             ]
    end

    test "inside text node" do
      # aaa<!--bbb-->ccc
      tags = [
        {:text, "aaa"},
        :public_comment_start,
        {:text, "bbb"},
        :public_comment_end,
        {:text, "ccc"}
      ]

      assert build_ast(tags) == [text: "aaa", public_comment: [text: "bbb"], text: "ccc"]
    end

    test "inside element node" do
      # <div><!--abc--></div>
      tags = [
        {:start_tag, {"div", []}},
        :public_comment_start,
        {:text, "abc"},
        :public_comment_end,
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [:element, "div", [key(tags, 0)], [public_comment: [text: "abc"]]]}
             ]
    end

    test "inside component node" do
      # <MyComponent><!--abc--></MyComponent>
      tags = [
        {:start_tag, {"MyComponent", []}},
        :public_comment_start,
        {:text, "abc"},
        :public_comment_end,
        {:end_tag, "MyComponent"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  [public_comment: [text: "abc"]]
                ]}
             ]
    end

    test "after text node" do
      # aaa<!--bbb-->
      tags = [{:text, "aaa"}, :public_comment_start, {:text, "bbb"}, :public_comment_end]

      assert build_ast(tags) == [text: "aaa", public_comment: [text: "bbb"]]
    end

    test "after element node" do
      # <div></div><!--abc-->
      tags = [
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        :public_comment_start,
        {:text, "abc"},
        :public_comment_end
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]},
               {:public_comment, [text: "abc"]}
             ]
    end

    test "after component node" do
      # <MyComponent></MyComponent><!--abc-->
      tags = [
        {:start_tag, {"MyComponent", []}},
        {:end_tag, "MyComponent"},
        :public_comment_start,
        {:text, "abc"},
        :public_comment_end
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  []
                ]},
               {:public_comment, [text: "abc"]}
             ]
    end

    test "before text node" do
      # <!--aaa-->bbb
      tags = [:public_comment_start, {:text, "aaa"}, :public_comment_end, {:text, "bbb"}]

      assert build_ast(tags) == [public_comment: [text: "aaa"], text: "bbb"]
    end

    test "before element node" do
      # <!--aaa--><div></div>
      tags = [
        :public_comment_start,
        {:text, "aaa"},
        :public_comment_end,
        {:start_tag, {"div", []}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:public_comment, [text: "aaa"]},
               {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}
             ]
    end

    test "before component node" do
      # <!--abc--><MyComponent></MyComponent>
      tags = [
        :public_comment_start,
        {:text, "abc"},
        :public_comment_end,
        {:start_tag, {"MyComponent", []}},
        {:end_tag, "MyComponent"}
      ]

      assert build_ast(tags) == [
               {:public_comment, [text: "abc"]},
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  []
                ]}
             ]
    end
  end

  describe "build_ast/1, DOCTYPE node" do
    test "empty" do
      # "<!DOCTYPE>"
      tags = [doctype: "html"]

      assert build_ast(tags) == [doctype: "html"]
    end

    test "inside component node" do
      # <MyComponent><!DOCTYPE html></MyComponent>
      tags = [
        {:start_tag, {"MyComponent", []}},
        {:doctype, "html"},
        {:end_tag, "MyComponent"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  [doctype: "html"]
                ]}
             ]
    end

    test "after text node with whitespaces" do
      # \r\n <!DOCTYPE html>
      tags = [text: "\r\n ", doctype: "html"]

      assert build_ast(tags) == [text: "\r\n ", doctype: "html"]
    end

    test "before text node with whitespaces" do
      # <!DOCTYPE html> \r\n
      tags = [doctype: "html", text: " \r\n"]

      assert build_ast(tags) == [doctype: "html", text: " \r\n"]
    end

    test "before element node" do
      # <!DOCTYPE html><div></div>
      tags = [
        {:doctype, "html"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:doctype, "html"},
               {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}
             ]
    end

    test "before component node" do
      # <!DOCTYPE html><MyComponent></MyComponent>
      tags = [
        {:doctype, "html"},
        {:start_tag, {"MyComponent", []}},
        {:end_tag, "MyComponent"}
      ]

      assert build_ast(tags) == [
               {:doctype, "html"},
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  []
                ]}
             ]
    end
  end

  describe "build_ast/1, element node & component node" do
    nodes = [
      {:element, "attribute", "div", "div"},
      {:component, "property", "Aaa.Bbb",
       quote do
         {:alias!, [line: 1], [{:__aliases__, [line: 1], [:Aaa, :Bbb]}]}
       end}
    ]

    Enum.each(nodes, fn {tag_type, attr_or_prop, tag_name, expected_tag_name_ast} ->
      test "#{tag_type} node without #{attr_or_prop}(s) or children" do
        # <div></div>
        # or
        # <Aaa.Bbb></Aaa.Bbb>
        tags = [{:start_tag, {unquote(tag_name), []}}, {:end_tag, unquote(tag_name)}]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "#{tag_type} node with single #{attr_or_prop}" do
        # <div my_key="my_value"></div>
        # or
        # <Aaa.Bbb my_key="my_value"></Aaa.Bbb>
        tags = [
          {:start_tag, {unquote(tag_name), [{"my_key", [text: "my_value"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) ==
                 [
                   {:{}, [line: 1],
                    [
                      unquote(tag_type),
                      unquote(expected_tag_name_ast),
                      [{"my_key", [text: "my_value"]}] ++ key_attrs(unquote(tag_type), tags, 0),
                      []
                    ]}
                 ]
      end

      test "#{tag_type} node, with multiple #{attr_or_prop}(s)" do
        # <div my_key_1="my_value_1" my_key_2="my_value_2"></div>
        # or
        # <Aaa.Bbb my_key_1="my_value_1" my_key_2="my_value_2"></Aaa.Bbb>
        tags = [
          {:start_tag,
           {unquote(tag_name),
            [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "#{tag_type} node #{attr_or_prop} with multiple value parts" do
        tags = [
          {:start_tag,
           {unquote(tag_name), [{"my_key", [text: "my_value_1", text: "my_value_2"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [{"my_key", [text: "my_value_1", text: "my_value_2"]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "#{tag_type} node with text child" do
        tags = [
          {:start_tag, {unquote(tag_name), []}},
          {:text, "abc"},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    key_attrs(unquote(tag_type), tags, 0),
                    [{:text, "abc"}]
                  ]}
               ]
      end

      test "#{tag_type} node with element child" do
        tags = [
          {:start_tag, {unquote(tag_name), []}},
          {:start_tag, {"span", []}},
          {:end_tag, "span"},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    key_attrs(unquote(tag_type), tags, 0),
                    [
                      {:{}, [line: 1],
                       [:element, "span", [key(tags, key_offset(unquote(tag_type)))], []]}
                    ]
                  ]}
               ]
      end

      test "#{tag_type} node with component child" do
        tags = [
          {:start_tag, {unquote(tag_name), []}},
          {:start_tag, {"Xxx.Yyy", []}},
          {:end_tag, "Xxx.Yyy"},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    key_attrs(unquote(tag_type), tags, 0),
                    [
                      {:{}, [line: 1],
                       [
                         :component,
                         {:alias!, [line: 1], [{:__aliases__, [line: 1], [:Xxx, :Yyy]}]},
                         [],
                         []
                       ]}
                    ]
                  ]}
               ]
      end

      test "#{tag_type} node with multiple children" do
        tags = [
          {:start_tag, {unquote(tag_name), []}},
          {:start_tag, {"span", []}},
          {:end_tag, "span"},
          {:text, "abc"},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    key_attrs(unquote(tag_type), tags, 0),
                    [
                      {:{}, [line: 1],
                       [:element, "span", [key(tags, key_offset(unquote(tag_type)))], []]},
                      {:text, "abc"}
                    ]
                  ]}
               ]
      end

      test "self-closing #{tag_type} node, not nested, without siblings" do
        tags = [
          {:self_closing_tag,
           {unquote(tag_name),
            [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "self-closing #{tag_type} node, not nested, with siblings" do
        tags = [
          {:text, "abc"},
          {:self_closing_tag,
           {unquote(tag_name),
            [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}},
          {:text, "xyz"}
        ]

        assert build_ast(tags) == [
                 {:text, "abc"},
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]},
                 {:text, "xyz"}
               ]
      end

      test "self-closing #{tag_type} node, nested, without siblings" do
        tags = [
          {:start_tag, {"div", []}},
          {:self_closing_tag,
           {unquote(tag_name),
            [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}},
          {:end_tag, "div"}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    :element,
                    "div",
                    [key(tags, 0)],
                    [
                      {:{}, [line: 1],
                       [
                         unquote(tag_type),
                         unquote(expected_tag_name_ast),
                         [
                           {"my_key_1", [text: "my_value_1"]},
                           {"my_key_2", [text: "my_value_2"]}
                         ] ++ key_attrs(unquote(tag_type), tags, 1),
                         []
                       ]}
                    ]
                  ]}
               ]
      end

      test "self-closing #{tag_type} node, nested, with siblings" do
        tags = [
          {:start_tag, {"div", []}},
          {:text, "abc"},
          {:self_closing_tag,
           {unquote(tag_name),
            [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}},
          {:text, "xyz"},
          {:end_tag, "div"}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    :element,
                    "div",
                    [key(tags, 0)],
                    [
                      {:text, "abc"},
                      {:{}, [line: 1],
                       [
                         unquote(tag_type),
                         unquote(expected_tag_name_ast),
                         [
                           {"my_key_1", [text: "my_value_1"]},
                           {"my_key_2", [text: "my_value_2"]}
                         ] ++ key_attrs(unquote(tag_type), tags, 1),
                         []
                       ]},
                      {:text, "xyz"}
                    ]
                  ]}
               ]
      end
    end)

    # A tag whose first char is uppercase is a component, so the element branch only ever sees a
    # name that starts lowercase. That is where the case a template wrote can still differ from the
    # case the parser produces.
    test "element node with uppercase chars in its tag name" do
      # <dIV></dIV>
      tags = [{:start_tag, {"dIV", []}}, {:end_tag, "dIV"}]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}
             ]
    end

    test "element node with an SVG tag name that lost its case" do
      # <lineargradient></lineargradient>
      tags = [{:start_tag, {"lineargradient", []}}, {:end_tag, "lineargradient"}]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "linearGradient", [key(tags, 0)], []]}
             ]
    end

    test "element node with an SVG tag name already spelled the way the parser spells it" do
      # <linearGradient></linearGradient>
      tags = [{:start_tag, {"linearGradient", []}}, {:end_tag, "linearGradient"}]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "linearGradient", [key(tags, 0)], []]}
             ]
    end

    test "self-closing element node with an SVG tag name that lost its case" do
      # <lineargradient />
      tags = [{:self_closing_tag, {"lineargradient", []}}]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "linearGradient", [key(tags, 0)], []]}
             ]
    end
  end

  describe "build_ast/1, dynamic tag node" do
    test "without attributes or children" do
      # <{"div"}></{"div"}>
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, []}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:dynamic_tag, {:{}, [line: 1], ["div"]}, [key(tags, 0)], []]}
             ]
    end

    test "with module attribute in tag name expression" do
      # <{@module}></{@module}>
      tags = [
        {:start_tag, {{:expression, "{@module}"}, []}},
        {:end_tag, {:expression, "{@module}"}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1],
                   [
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :module]},
                      [no_parens: true, line: 1], []}
                   ]},
                  [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with alias in tag name expression" do
      # <{Aaa.Bbb}></{Aaa.Bbb}>
      tags = [
        {:start_tag, {{:expression, "{Aaa.Bbb}"}, []}},
        {:end_tag, {:expression, "{Aaa.Bbb}"}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], [{:__aliases__, [line: 1], [:Aaa, :Bbb]}]},
                  [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with function call in tag name expression" do
      # <{my_fun(1)}></{my_fun(1)}>
      tags = [
        {:start_tag, {{:expression, "{my_fun(1)}"}, []}},
        {:end_tag, {:expression, "{my_fun(1)}"}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], [{:my_fun, [line: 1], [1]}]},
                  [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with single attribute" do
      # <{"div"} my_key="my_value"></{"div"}>
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, [{"my_key", [text: "my_value"]}]}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [{"my_key", [text: "my_value"]}] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with multiple attributes" do
      tags = [
        {:start_tag,
         {{:expression, ~s({"div"})},
          [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [
                    {"my_key_1", [text: "my_value_1"]},
                    {"my_key_2", [text: "my_value_2"]},
                    key(tags, 0)
                  ],
                  []
                ]}
             ]
    end

    test "with attribute having expression value" do
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, [{"my_key", [expression: "{1 + 2}"]}]}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [{"my_key", [expression: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]}]}] ++
                    [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with event attribute" do
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, [{"$click", [text: "my_action"]}]}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [{"$click", [text: "my_action"]}] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    # Event modifiers are decomposed the element way, since the element branch is the only one
    # that can consume events.
    test "with event attribute having modifiers" do
      tags = [
        {:start_tag,
         {{:expression, ~s({"div"})}, [{"$click.debounce(500)", [text: "my_action"]}]}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [
                    {:{}, [line: 1],
                     ["$click", [text: "my_action"], {:%{}, [line: 1], [debounce: 500]}]}
                  ] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with spread" do
      # <{"div"} ...{@my_var}></{"div"}>
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, [{:spread, "{@my_var}"}]}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [
                    spread:
                      {:{}, [line: 1],
                       [
                         {{:., [line: 1], [{:vars, [line: 1], nil}, :my_var]},
                          [no_parens: true, line: 1], []}
                       ]}
                  ] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "with text child" do
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, []}},
        {:text, "abc"},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [:dynamic_tag, {:{}, [line: 1], ["div"]}, [key(tags, 0)], [{:text, "abc"}]]}
             ]
    end

    test "with element child" do
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, []}},
        {:start_tag, {"span", []}},
        {:end_tag, "span"},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [key(tags, 0)],
                  [{:{}, [line: 1], [:element, "span", [key(tags, 1)], []]}]
                ]}
             ]
    end

    test "with dynamic tag child" do
      tags = [
        {:start_tag, {{:expression, ~s({"div"})}, []}},
        {:start_tag, {{:expression, ~s({"span"})}, []}},
        {:end_tag, {:expression, ~s({"span"})}},
        {:end_tag, {:expression, ~s({"div"})}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [key(tags, 0)],
                  [
                    {:{}, [line: 1],
                     [:dynamic_tag, {:{}, [line: 1], ["span"]}, [key(tags, 1)], []]}
                  ]
                ]}
             ]
    end

    test "self-closing, not nested, without siblings" do
      # <{"div"} my_key="my_value" />
      tags = [
        {:self_closing_tag, {{:expression, ~s({"div"})}, [{"my_key", [text: "my_value"]}]}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["div"]},
                  [{"my_key", [text: "my_value"]}] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "self-closing, nested, with siblings" do
      tags = [
        {:start_tag, {"div", []}},
        {:text, "abc"},
        {:self_closing_tag, {{:expression, ~s({"span"})}, []}},
        {:text, "xyz"},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [key(tags, 0)],
                  [
                    {:text, "abc"},
                    {:{}, [line: 1],
                     [:dynamic_tag, {:{}, [line: 1], ["span"]}, [key(tags, 1)], []]},
                    {:text, "xyz"}
                  ]
                ]}
             ]
    end

    test "inside if block" do
      tags = [
        {:block_start, {"if", "{ @flag}"}},
        {:self_closing_tag, {{:expression, ~s({"div"})}, []}},
        {:block_end, "if"}
      ]

      assert build_ast(tags) == [
               {:if, [line: 1],
                [
                  {{:., [line: 1], [{:vars, [line: 1], nil}, :flag]}, [no_parens: true, line: 1],
                   []},
                  [
                    do: [
                      {:{}, [line: 1],
                       [:dynamic_tag, {:{}, [line: 1], ["div"]}, [key(tags, 0)], []]}
                    ]
                  ]
                ]}
             ]
    end
  end

  describe "build_ast/1, spread" do
    nodes = [
      {:element, "attribute", "div", "div"},
      {:component, "property", "Aaa.Bbb",
       quote do
         {:alias!, [line: 1], [{:__aliases__, [line: 1], [:Aaa, :Bbb]}]}
       end}
    ]

    Enum.each(nodes, fn {tag_type, attr_or_prop, tag_name, expected_tag_name_ast} ->
      test "single spread in #{tag_type} node" do
        # <div ...{@my_var}></div>
        # or
        # <Aaa.Bbb ...{@my_var}></Aaa.Bbb>
        tags = [
          {:start_tag, {unquote(tag_name), [{:spread, "{@my_var}"}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [
                      spread:
                        {:{}, [line: 1],
                         [
                           {{:., [line: 1], [{:vars, [line: 1], nil}, :my_var]},
                            [no_parens: true, line: 1], []}
                         ]}
                    ] ++ key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "multiple spreads in #{tag_type} node" do
        tags = [
          {:start_tag, {unquote(tag_name), [{:spread, "{1 + 2}"}, {:spread, "{3 + 4}"}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [
                      spread: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]},
                      spread: {:{}, [line: 1], [{:+, [line: 1], [3, 4]}]}
                    ] ++ key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "spread interleaved with named #{tag_type} #{attr_or_prop}(s), preserving order" do
        tags = [
          {:start_tag,
           {unquote(tag_name),
            [
              {"my_key_1", [text: "my_value_1"]},
              {:spread, "{1 + 2}"},
              {"my_key_2", [text: "my_value_2"]}
            ]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [
                      {"my_key_1", [text: "my_value_1"]},
                      {:spread, {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]}},
                      {"my_key_2", [text: "my_value_2"]}
                    ] ++ key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "spread in self-closing #{tag_type} node" do
        tags = [{:self_closing_tag, {unquote(tag_name), [{:spread, "{1 + 2}"}]}}]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [spread: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "spread with map expression in #{tag_type} node" do
        tags = [
          {:start_tag, {unquote(tag_name), [{:spread, "{%{my_key: 1}}"}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [spread: {:{}, [line: 1], [{:%{}, [line: 1], [my_key: 1]}]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "spread with implicit keyword list in #{tag_type} node" do
        tags = [
          {:start_tag, {unquote(tag_name), [{:spread, "{my_key_1: 1, my_key_2: 2}"}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [spread: {:{}, [line: 1], [[my_key_1: 1, my_key_2: 2]]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end
    end)

    test "spread with implicit keyword list, spanning multiple lines" do
      tags = [
        {:start_tag, {"div", [{:spread, "{\n  my_key_1: 1,\n  my_key_2: 2\n}"}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [spread: {:{}, [line: 1], [[my_key_1: 1, my_key_2: 2]]}] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "spread with implicit keyword list, starting with a key with double quotes" do
      tags = [
        {:start_tag, {"div", [{:spread, ~s'{"aaa bbb": 1, c: 2}'}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [spread: {:{}, [line: 1], [["aaa bbb": 1, c: 2]]}] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end
  end

  describe "build_ast/1, element event attribute with modifiers" do
    test "no modifier stays a 2-tuple" do
      # <div $key_down="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$key_down", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [:element, "div", [{"$key_down", [text: "my_value"]}, key(tags, 0)], []]}
             ]
    end

    test "keyboard event with a single key filter" do
      # <div $key_down.enter="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$key_down.enter", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [
                    {:{}, [line: 1],
                     [
                       "$key_down",
                       [text: "my_value"],
                       {:%{}, [line: 1], [key: [["enter"]]]}
                     ]}
                  ] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "keyboard event with a combined key filter" do
      # <div $key_down.ctrl+k="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$key_down.ctrl+k", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [
                    {:{}, [line: 1],
                     [
                       "$key_down",
                       [text: "my_value"],
                       {:%{}, [line: 1], [key: [["ctrl", "k"]]]}
                     ]}
                  ] ++ [key(tags, 0)],
                  []
                ]}
             ]
    end

    test "non-keyboard event with a debounce modifier" do
      # <div $click.debounce(500)="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$click.debounce(500)", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [
                    {:{}, [line: 1],
                     [
                       "$click",
                       [text: "my_value"],
                       {:%{}, [line: 1], [debounce: 500]}
                     ]},
                    key(tags, 0)
                  ],
                  []
                ]}
             ]
    end

    test "non-keyboard event with a once modifier" do
      # The boolean modifier's `true` value survives inspect -> code -> AST.for_code quoted, reaching
      # the client as the atom true rather than a string.
      # <div $click.once="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$click.once", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [
                    {:{}, [line: 1],
                     [
                       "$click",
                       [text: "my_value"],
                       {:%{}, [line: 1], [once: true]}
                     ]},
                    key(tags, 0)
                  ],
                  []
                ]}
             ]
    end

    test "reach event with a px within modifier" do
      # <div $reach_bottom.within(200px)="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$reach_bottom.within(200px)", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [
                    {:{}, [line: 1],
                     [
                       "$reach_bottom",
                       [text: "my_value"],
                       {:%{}, [line: 1], [within: "200px"]}
                     ]},
                    key(tags, 0)
                  ],
                  []
                ]}
             ]
    end

    test "reach event with a percentage within modifier" do
      # The "%" character is map syntax in Elixir source, so this locks that a within value survives
      # inspect -> code -> AST.for_code quoted, reaching the client as the plain string "50%".
      # <div $reach_top.within(50%)="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$reach_top.within(50%)", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [
                    {:{}, [line: 1],
                     [
                       "$reach_top",
                       [text: "my_value"],
                       {:%{}, [line: 1], [within: "50%"]}
                     ]},
                    key(tags, 0)
                  ],
                  []
                ]}
             ]
    end

    test "raises for an unknown key in a keyboard event" do
      # <div $key_down.entr="my_value"></div>
      tags = [
        {:start_tag, {"div", [{"$key_down.entr", [text: "my_value"]}]}},
        {:end_tag, "div"}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'unknown keyboard key "entr". Did you mean "enter"?',
                   fn -> build_ast(tags) end
    end

    test "component $-attribute is not decomposed" do
      # <Aaa.Bbb $key_down.enter="my_value"></Aaa.Bbb>
      tags = [
        {:start_tag, {"Aaa.Bbb", [{"$key_down.enter", [text: "my_value"]}]}},
        {:end_tag, "Aaa.Bbb"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:Aaa, :Bbb]}]},
                  [{"$key_down.enter", [text: "my_value"]}],
                  []
                ]}
             ]
    end
  end

  describe "build_ast/1, $focused attribute" do
    test "with an expression stays a 2-tuple" do
      # <input $focused={true} />
      tags = [{:self_closing_tag, {"input", [{"$focused", [expression: "{true}"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "input",
                  [{"$focused", [expression: {:{}, [line: 1], [true]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "bare stays a 2-tuple with an empty value" do
      # <input $focused />
      tags = [{:self_closing_tag, {"input", [{"$focused", []}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "input", [{"$focused", []}, key(tags, 0)], []]}
             ]
    end

    test "on a dynamic tag" do
      # <{"input"} $focused={true} />
      tags = [
        {:self_closing_tag,
         {{:expression, ~s({"input"})}, [{"$focused", [expression: "{true}"]}]}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["input"]},
                  [{"$focused", [expression: {:{}, [line: 1], [true]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "raises for a text value" do
      # <input $focused="handler" />
      tags = [{:self_closing_tag, {"input", [{"$focused", [text: "handler"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   "the $focused attribute takes a single expression, like $focused={@editing?}",
                   fn -> build_ast(tags) end
    end

    test "raises for a mixed value" do
      # <input $focused="a{true}" />
      tags = [
        {:self_closing_tag, {"input", [{"$focused", [text: "a", expression: "{true}"]}]}}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "the $focused attribute takes a single expression, like $focused={@editing?}",
                   fn -> build_ast(tags) end
    end

    test "raises for a modifier" do
      # <input $focused.once={true} />
      tags = [{:self_closing_tag, {"input", [{"$focused.once", [expression: "{true}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the $focused attribute takes no modifiers, got "once"',
                   fn -> build_ast(tags) end
    end

    test "raises next to a literal autofocus" do
      # <input autofocus $focused={true} />
      tags = [
        {:self_closing_tag, {"input", [{"autofocus", []}, {"$focused", [expression: "{true}"]}]}}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "an element takes either the autofocus attribute or $focused, not both",
                   fn -> build_ast(tags) end
    end

    test "raises next to a literal autofocus on a dynamic tag" do
      # <{"input"} $focused={true} autofocus={true} />
      tags = [
        {:self_closing_tag,
         {{:expression, ~s({"input"})},
          [{"$focused", [expression: "{true}"]}, {"autofocus", [expression: "{true}"]}]}}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "an element takes either the autofocus attribute or $focused, not both",
                   fn -> build_ast(tags) end
    end

    test "a literal autofocus alone passes" do
      # <input autofocus />
      tags = [{:self_closing_tag, {"input", [{"autofocus", []}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1], [:element, "input", [{"autofocus", []}, key(tags, 0)], []]}
             ]
    end

    test "raises on the window tag" do
      # <window $focused={true} />
      tags = [{:self_closing_tag, {"window", [{"$focused", [expression: "{true}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <window> tag accepts only event bindings, but got the "$focused" attribute',
                   fn -> build_ast(tags) end
    end

    test "raises on the window tag with a modifier" do
      # <window $focused.once={true} />
      tags = [{:self_closing_tag, {"window", [{"$focused.once", [expression: "{true}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <window> tag accepts only event bindings, but got the "$focused.once" attribute',
                   fn -> build_ast(tags) end
    end

    test "raises on the document tag" do
      # <document $focused={true} />
      tags = [{:self_closing_tag, {"document", [{"$focused", [expression: "{true}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <document> tag accepts only event bindings, but got the "$focused" attribute',
                   fn -> build_ast(tags) end
    end
  end

  describe "build_ast/1, $ref attribute" do
    test "text form becomes the atom it spells" do
      # <input $ref="search" />
      tags = [{:self_closing_tag, {"input", [{"$ref", [text: "search"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "input",
                  [{"$ref", [expression: {:{}, [line: 1], [:search]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "text form takes any name an atom can be written with without quotes" do
      # <input $ref="café?" />
      tags = [{:self_closing_tag, {"input", [{"$ref", [text: "café?"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "input",
                  [{"$ref", [expression: {:{}, [line: 1], [:café?]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "expression form stays as written" do
      # <li $ref={:message, 42} />
      tags = [{:self_closing_tag, {"li", [{"$ref", [expression: "{:message, 42}"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [:element, "li", [{"$ref", [expression: {:message, 42}]}, key(tags, 0)], []]}
             ]
    end

    test "a tuple wrapped in its own braces stays as written" do
      # <li $ref={{:message, 42}} />
      tags = [{:self_closing_tag, {"li", [{"$ref", [expression: "{{:message, 42}}"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "li",
                  [{"$ref", [expression: {:{}, [line: 1], [{:message, 42}]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "on a dynamic tag" do
      # <{"input"} $ref="search" />
      tags = [
        {:self_closing_tag, {{:expression, ~s({"input"})}, [{"$ref", [text: "search"]}]}}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :dynamic_tag,
                  {:{}, [line: 1], ["input"]},
                  [{"$ref", [expression: {:{}, [line: 1], [:search]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "raises for text form that isn't a plain atom name" do
      for {text, hint} <- [{"my-search", ~s'{:"my-search"}'}, {"Search", "{:Search}"}] do
        # <input $ref="my-search" />
        tags = [{:self_closing_tag, {"input", [{"$ref", [text: text]}]}}]

        assert_raise Hologram.TemplateSyntaxError,
                     ~s'the text form of $ref takes a plain atom name, like $ref="search", got "#{text}" - ' <>
                       "write any other ref as an expression, like $ref=#{hint}",
                     fn -> build_ast(tags) end
      end
    end

    test "raises for text form that names nil, true or false" do
      for text <- ["nil", "true", "false"] do
        # <input $ref="nil" />
        tags = [{:self_closing_tag, {"input", [{"$ref", [text: text]}]}}]

        assert_raise Hologram.TemplateSyntaxError,
                     "$ref takes an identifier, like :search or {:message, 42}, got: #{text} - nil, true and false can't be in an identifier",
                     fn -> build_ast(tags) end
      end
    end

    test "raises for a built-in ref in text form" do
      # <div $ref="window" />
      tags = [{:self_closing_tag, {"div", [{"$ref", [text: "window"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ":window is a built-in ref, so a template can't name an element with it - JS.element(:window) returns the window",
                   fn -> build_ast(tags) end
    end

    test "raises for a built-in ref written as a literal expression" do
      # <div $ref={:document} />
      tags = [{:self_closing_tag, {"div", [{"$ref", [expression: "{:document}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ":document is a built-in ref, so a template can't name an element with it - JS.element(:document) returns the document",
                   fn -> build_ast(tags) end
    end

    test "raises for a built-in ref on a dynamic tag" do
      # <{"div"} $ref="document" />
      tags = [
        {:self_closing_tag, {{:expression, ~s({"div"})}, [{"$ref", [text: "document"]}]}}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   ":document is a built-in ref, so a template can't name an element with it - JS.element(:document) returns the document",
                   fn -> build_ast(tags) end
    end

    test "raises for a missing value and a mixed value" do
      # <input $ref /> and <input $ref="a{@ref}" />
      for value_parts <- [[], [text: "a", expression: "{@ref}"]] do
        tags = [{:self_closing_tag, {"input", [{"$ref", value_parts}]}}]

        assert_raise Hologram.TemplateSyntaxError,
                     ~s'the $ref attribute takes a name, like $ref="search", or a single expression, like $ref={:message, message.id}',
                     fn -> build_ast(tags) end
      end
    end

    test "raises for an empty text form" do
      # <input $ref="" />
      tags = [{:self_closing_tag, {"input", [{"$ref", [text: ""]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the text form of $ref takes a plain atom name, like $ref="search", got "" - ' <>
                     ~s'write any other ref as an expression, like $ref={:""}',
                   fn -> build_ast(tags) end
    end

    test "raises for a quoted expression" do
      tags = Parser.parse_markup(~s'<input $ref="{@ref}" />')

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the $ref attribute takes a name, like $ref="search", or a single expression, like $ref={:message, message.id}',
                   fn -> build_ast(tags) end
    end

    test "raises for a modifier" do
      # <input $ref.once="search" />
      tags = [{:self_closing_tag, {"input", [{"$ref.once", [text: "search"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the $ref attribute takes no modifiers, got "once"',
                   fn -> build_ast(tags) end
    end

    test "raises for two $ref attributes" do
      # <input $ref="a" $ref="b" />
      tags = [
        {:self_closing_tag, {"input", [{"$ref", [text: "a"]}, {"$ref", [text: "b"]}]}}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "a tag takes one $ref attribute",
                   fn -> build_ast(tags) end
    end

    test "raises for two $ref attributes on a dynamic tag" do
      # <{"input"} $ref="a" $ref="b" />
      tags = [
        {:self_closing_tag,
         {{:expression, ~s({"input"})}, [{"$ref", [text: "a"]}, {"$ref", [text: "b"]}]}}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "a tag takes one $ref attribute",
                   fn -> build_ast(tags) end
    end

    test "raises on a component tag" do
      # <SearchBox $ref="search" />
      tags = [{:self_closing_tag, {"SearchBox", [{"$ref", [text: "search"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   "$ref can't go on the <SearchBox> component tag - a component renders no element of its own, " <>
                     "so put $ref on an element in its template and pass the ref as a prop, like input_ref={:search}",
                   fn -> build_ast(tags) end
    end

    test "raises on the window and document tags" do
      for tag_name <- ["window", "document"] do
        # <window $ref="viewport" />
        tags = [{:self_closing_tag, {tag_name, [{"$ref", [text: "viewport"]}]}}]

        assert_raise Hologram.TemplateSyntaxError,
                     "$ref can't go on a <#{tag_name}> tag, which renders no element - JS.element(:#{tag_name}) returns the #{tag_name}",
                     fn -> build_ast(tags) end
      end
    end

    test "raises on the slot tag" do
      # <slot $ref="content" />
      tags = [{:self_closing_tag, {"slot", [{"$ref", [text: "content"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   "$ref can't go on a <slot> tag, which renders no element of its own - put it on an element in the slot content",
                   fn -> build_ast(tags) end
    end

    test "raises on the html tag" do
      # <html $ref="root"></html>
      tags = [{:start_tag, {"html", [{"$ref", [text: "root"]}]}}, {:end_tag, "html"}]

      assert_raise Hologram.TemplateSyntaxError,
                   "$ref can't go on the <html> tag - JS.element(:document) returns the document, whose documentElement is the <html> element",
                   fn -> build_ast(tags) end
    end

    test "can go on the head and body tags" do
      for tag_name <- ["head", "body"] do
        # <body $ref="page_part"></body>
        tags = [{:start_tag, {tag_name, [{"$ref", [text: "page_part"]}]}}, {:end_tag, tag_name}]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    :element,
                    tag_name,
                    [{"$ref", [expression: {:{}, [line: 1], [:page_part]}]}],
                    []
                  ]}
               ]
      end
    end
  end

  describe "build_ast/1, true event binding value" do
    test "raises for a literal true" do
      # <button $click={true}></button>
      tags = [
        {:start_tag, {"button", [{"$click", [expression: "{true}"]}]}},
        {:end_tag, "button"}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "the $click binding takes an action or command, got true",
                   fn -> build_ast(tags) end
    end

    test "a literal false passes" do
      # <button $click={false}></button>
      tags = [
        {:start_tag, {"button", [{"$click", [expression: "{false}"]}]}},
        {:end_tag, "button"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "button",
                  [{"$click", [expression: {:{}, [line: 1], [false]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end

    test "raises with the $focused hint for $focus" do
      # <input $focus={true} />
      tags = [{:self_closing_tag, {"input", [{"$focus", [expression: "{true}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   "the $focus binding takes an action or command, got true - to control focus, use $focused",
                   fn -> build_ast(tags) end
    end

    test "raises for a modifier form too" do
      # <button $click.once={true}></button>
      tags = [
        {:start_tag, {"button", [{"$click.once", [expression: "{true}"]}]}},
        {:end_tag, "button"}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "the $click binding takes an action or command, got true",
                   fn -> build_ast(tags) end
    end

    test "an expression that is not a literal boolean passes" do
      # <button $click={@action}></button>
      tags = [
        {:start_tag, {"button", [{"$click", [expression: "{@action}"]}]}},
        {:end_tag, "button"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "button",
                  [
                    {"$click",
                     [
                       expression:
                         {:{}, [line: 1],
                          [
                            {{:., [line: 1], [{:vars, [line: 1], nil}, :action]},
                             [no_parens: true, line: 1], []}
                          ]}
                     ]},
                    key(tags, 0)
                  ],
                  []
                ]}
             ]
    end

    test "raises for a literal atom-syntax boolean" do
      # <button $click={:true}></button>
      tags = [
        {:start_tag, {"button", [{"$click", [expression: "{:true}"]}]}},
        {:end_tag, "button"}
      ]

      assert_raise Hologram.TemplateSyntaxError,
                   "the $click binding takes an action or command, got :true",
                   fn -> build_ast(tags) end
    end

    test "a plain attribute with a literal boolean passes" do
      # <button disabled={true}></button>
      tags = [
        {:start_tag, {"button", [{"disabled", [expression: "{true}"]}]}},
        {:end_tag, "button"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "button",
                  [{"disabled", [expression: {:{}, [line: 1], [true]}]}, key(tags, 0)],
                  []
                ]}
             ]
    end
  end

  describe "build_ast/1, page-level tags" do
    # Each is the only one of its kind, so a key cannot tell it from a sibling, and the patch
    # reaches all three by name rather than through an ordinary children diff - a key there would
    # make it rebuild them instead.
    test "carry no key" do
      # <html><head></head><body></body></html>
      tags = [
        {:start_tag, {"html", []}},
        {:start_tag, {"head", []}},
        {:end_tag, "head"},
        {:start_tag, {"body", []}},
        {:end_tag, "body"},
        {:end_tag, "html"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "html",
                  [],
                  [
                    {:{}, [line: 1], [:element, "head", [], []]},
                    {:{}, [line: 1], [:element, "body", [], []]}
                  ]
                ]}
             ]
    end

    test "don't take a key index from the elements they hold" do
      # <html><body><div></div></body></html>
      tags = [
        {:start_tag, {"html", []}},
        {:start_tag, {"body", []}},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        {:end_tag, "body"},
        {:end_tag, "html"}
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "html",
                  [],
                  [
                    {:{}, [line: 1],
                     [
                       :element,
                       "body",
                       [],
                       [{:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}]
                     ]}
                  ]
                ]}
             ]
    end
  end

  describe "build_ast/1, window tag" do
    test "with an event binding" do
      # <window $key_down.ctrl+k="open_palette" />
      tags = [{:self_closing_tag, {"window", [{"$key_down.ctrl+k", [text: "open_palette"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "window",
                  [
                    {:{}, [line: 1],
                     [
                       "$key_down",
                       [text: "open_palette"],
                       {:%{}, [line: 1], [key: [["ctrl", "k"]]]}
                     ]}
                  ],
                  []
                ]}
             ]
    end

    test "raises for a non-event attribute" do
      # <window class="my_class" />
      tags = [{:self_closing_tag, {"window", [{"class", [text: "my_class"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <window> tag accepts only event bindings, but got the "class" attribute',
                   fn -> build_ast(tags) end
    end

    test "raises for a spread" do
      # <window ...{@my_var} />
      tags = [{:self_closing_tag, {"window", [{:spread, "{@my_var}"}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <window> tag accepts only event bindings, but got a spread',
                   fn -> build_ast(tags) end
    end
  end

  describe "build_ast/1, document tag" do
    test "with an event binding" do
      # <document $key_down.ctrl+k="open_palette" />
      tags = [{:self_closing_tag, {"document", [{"$key_down.ctrl+k", [text: "open_palette"]}]}}]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "document",
                  [
                    {:{}, [line: 1],
                     [
                       "$key_down",
                       [text: "open_palette"],
                       {:%{}, [line: 1], [key: [["ctrl", "k"]]]}
                     ]}
                  ],
                  []
                ]}
             ]
    end

    test "raises for a non-event attribute" do
      # <document class="my_class" />
      tags = [{:self_closing_tag, {"document", [{"class", [text: "my_class"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <document> tag accepts only event bindings, but got the "class" attribute',
                   fn -> build_ast(tags) end
    end

    test "raises for a spread" do
      # <document ...{@my_var} />
      tags = [{:self_closing_tag, {"document", [{:spread, "{@my_var}"}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the <document> tag accepts only event bindings, but got a spread',
                   fn -> build_ast(tags) end
    end
  end

  describe "build_ast/1, expression node" do
    test "in text" do
      tags = [{:text, "abc"}, {:expression, "{1 + 2}"}, {:text, "xyz"}]

      assert build_ast(tags) == [
               text: "abc",
               expression: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]},
               text: "xyz"
             ]
    end

    nodes = [
      {:element, "attribute", "div", "div"},
      {:component, "property", "Aaa.Bbb",
       quote do
         {:alias!, [line: 1], [{:__aliases__, [line: 1], [:Aaa, :Bbb]}]}
       end}
    ]

    Enum.each(nodes, fn {tag_type, attr_or_prop, tag_name, expected_tag_name_ast} ->
      test "in #{tag_type} #{attr_or_prop} value, with one part only" do
        tags = [
          {:start_tag, {unquote(tag_name), [{"my_key", [expression: "{1 + 2}"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [{"my_key", [expression: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]}]}] ++
                      key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "in #{tag_type} #{attr_or_prop} value, after text part" do
        tags = [
          {:start_tag,
           {unquote(tag_name), [{"my_key", [text: "my_value", expression: "{1 + 2}"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [
                      {"my_key",
                       [
                         text: "my_value",
                         expression: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]}
                       ]}
                    ] ++ key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "in #{tag_type} #{attr_or_prop} value, before text part" do
        tags = [
          {:start_tag,
           {unquote(tag_name), [{"my_key", [expression: "{1 + 2}", text: "my_value"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [
                      {"my_key",
                       [
                         expression: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]},
                         text: "my_value"
                       ]}
                    ] ++ key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end

      test "in #{tag_type} #{attr_or_prop} value, after another expression part" do
        tags = [
          {:start_tag,
           {unquote(tag_name), [{"my_key", [expression: "{1 + 2}", expression: "{@my_var * 9}"]}]}},
          {:end_tag, unquote(tag_name)}
        ]

        assert build_ast(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    unquote(expected_tag_name_ast),
                    [
                      {"my_key",
                       [
                         expression: {:{}, [line: 1], [{:+, [line: 1], [1, 2]}]},
                         expression:
                           {:{}, [line: 1],
                            [
                              {:*, [line: 1],
                               [
                                 {{:., [line: 1], [{:vars, [line: 1], nil}, :my_var]},
                                  [no_parens: true, line: 1], []},
                                 9
                               ]}
                            ]}
                       ]}
                    ] ++ key_attrs(unquote(tag_type), tags, 0),
                    []
                  ]}
               ]
      end
    end)

    test "with implicit keyword list, starting with a key without double quotes" do
      tags = [{:expression, "{a: 1, b: 2}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[a: 1, b: 2]]}]
    end

    test "with implicit keyword list, starting with a key with double quotes" do
      tags = [{:expression, ~s'{"aaa bbb": 1, c: 2}'}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [["aaa bbb": 1, c: 2]]}]
    end

    test "with implicit keyword list, starting with a key containing underscores" do
      tags = [{:expression, "{my_key_1: 1, my_key_2: 2}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[my_key_1: 1, my_key_2: 2]]}]
    end

    test "with implicit keyword list, starting with a key with a trailing question mark" do
      tags = [{:expression, "{my_key?: 1, b: 2}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[my_key?: 1, b: 2]]}]
    end

    test "with implicit keyword list, starting with a key with a trailing exclamation mark" do
      tags = [{:expression, "{my_key!: 1, b: 2}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[my_key!: 1, b: 2]]}]
    end

    test "with implicit keyword list, having whitespace after the opening curly bracket" do
      tags = [{:expression, "{ my_key_1: 1, my_key_2: 2}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[my_key_1: 1, my_key_2: 2]]}]
    end

    test "with implicit keyword list, spanning multiple lines" do
      tags = [{:expression, "{\n  my_key_1: 1,\n  my_key_2: 2\n}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[my_key_1: 1, my_key_2: 2]]}]
    end

    test "with implicit keyword list, having a newline after the colon" do
      tags = [{:expression, "{my_key:\n  1}"}]

      assert build_ast(tags) == [expression: {:{}, [line: 1], [[my_key: 1]]}]
    end
  end

  describe "build_ast/1, for block" do
    # The for block's loop item: the one-tuple holding the item the generator binds whole, and the
    # body's nodes.
    defp loop_item(nodes) do
      {:{}, [line: 1], [:loop_item, {:{}, [line: 1], [{:holo_loop_item, [line: 1], nil}]}, nodes]}
    end

    defp loop_item_var, do: {:holo_loop_item, [line: 1], nil}

    defp items_ast do
      {{:., [line: 1], [{:vars, [line: 1], nil}, :items]}, [no_parens: true, line: 1], []}
    end

    test "with one child" do
      tags = [{:block_start, {"for", "{ item <- @items}"}}, {:text, "abc"}, {:block_end, "for"}]

      assert build_ast(tags) == [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [{:=, [line: 1], [{:item, [line: 1], nil}, loop_item_var()]}, items_ast()]},
                  [do: {:__block__, [], [loop_item(text: "abc")]}]
                ]}
             ]
    end

    test "with multiple children" do
      tags = [
        {:block_start, {"for", "{ item <- @items}"}},
        {:text, "abc"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        {:block_end, "for"}
      ]

      assert build_ast(tags) == [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [{:=, [line: 1], [{:item, [line: 1], nil}, loop_item_var()]}, items_ast()]},
                  [
                    do:
                      {:__block__, [],
                       [
                         loop_item([
                           {:text, "abc"},
                           {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}
                         ])
                       ]}
                  ]
                ]}
             ]
    end

    test "without children" do
      tags = [{:block_start, {"for", "{ item <- @items}"}}, {:block_end, "for"}]

      assert [{:for, [line: 1], [_generator, [do: {:__block__, [], [loop_item]}]]}] =
               build_ast(tags)

      assert loop_item == loop_item([])
    end

    test "a destructuring pattern still binds the whole item" do
      tags = [
        {:block_start, {"for", "{ %{name: name} <- @items}"}},
        {:expression, "{name}"},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:=, [line: 1], [{:%{}, [line: 1], [name: {:name, [line: 1], nil}]}, var]},
                     _enum
                   ]},
                  _do
                ]}
             ] = build_ast(tags)

      assert var == loop_item_var()
    end

    test "a guard stays outside the match" do
      tags = [
        {:block_start, {"for", "{ item when item > 1 <- @items}"}},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:when, [line: 1],
                      [
                        {:=, [line: 1], [{:item, [line: 1], nil}, var]},
                        {:>, [line: 1], [{:item, [line: 1], nil}, 1]}
                      ]},
                     _enum
                   ]},
                  _do
                ]}
             ] = build_ast(tags)

      assert var == loop_item_var()
    end

    test "filters and options are kept" do
      tags = [
        {:block_start, {"for", "{ item <- @items, item != nil, into: []}"}},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:=, [line: 1], [{:item, [line: 1], nil}, _var]}, enum]},
                  {:!=, [line: 1], [{:item, [line: 1], nil}, nil]},
                  [into: []],
                  [do: {:__block__, [], [body]}]
                ]}
             ] = build_ast(tags)

      assert enum == items_ast()
      assert body == loop_item([])
    end

    test "two generators give no item" do
      tags = [
        {:block_start, {"for", "{ x <- @xs, y <- @ys}"}},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, _xs]},
                  {:<-, [line: 1], [{:y, [line: 1], nil}, _ys]},
                  [do: {:__block__, [], [{:{}, [line: 1], [:loop_item, nil, []]}]}]
                ]}
             ] = build_ast(tags)
    end

    test "patterns and qualifiers survive being printed back" do
      for {source, expected_qualifiers} <- [
            {"^x <- @items", "^x = holo_loop_item <- vars.items"},
            {"1 <- @items", "1 = holo_loop_item <- vars.items"},
            {~S|"a\"#b" <> rest <- @items|, ~S|"a\"#b" <> rest = holo_loop_item <- vars.items|},
            {"<<a::8, rest::binary>> <- @items",
             "<<a::8, rest::binary>> = holo_loop_item <- vars.items"},
            {"x <- ~w(a b)", "x = holo_loop_item <- ~w(a b)"},
            {"x <- @items, y = x * 2", "x = holo_loop_item <- vars.items, y = x * 2"},
            {"x <-\n  @items", "x = holo_loop_item <- vars.items"},
            {"x <- @items, into: @acc", "x = holo_loop_item <- vars.items, into: vars.acc"}
          ] do
        tags = [{:block_start, {"for", "{ #{source}}"}}, {:block_end, "for"}]

        expected =
          AST.for_code("[(for #{expected_qualifiers} do {:loop_item, {holo_loop_item}, []} end)]")

        assert build_ast(tags) == expected, "for #{source}"
      end
    end

    test "the uniq option gives no item" do
      tags = [
        {:block_start, {"for", "{ item <- @items, uniq: true}"}},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:item, [line: 1], nil}, _items]},
                  [uniq: true],
                  [do: {:__block__, [], [{:{}, [line: 1], [:loop_item, nil, []]}]}]
                ]}
             ] = build_ast(tags)
    end

    test "a bitstring generator next to a list generator gives no item" do
      tags = [
        {:block_start, {"for", "{ <<c <- @bytes>>, item <- @items}"}},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<<>>, [line: 1], [{:<-, [line: 1], [{:c, [line: 1], nil}, _bytes]}]},
                  {:<-, [line: 1], [{:item, [line: 1], nil}, _items]},
                  [do: {:__block__, [], [{:{}, [line: 1], [:loop_item, nil, []]}]}]
                ]}
             ] = build_ast(tags)
    end

    test "a bitstring generator gives no item" do
      tags = [
        {:block_start, {"for", "{ <<c <- @bytes>>}"}},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<<>>, [line: 1], [{:<-, [line: 1], [{:c, [line: 1], nil}, _bytes]}]},
                  [do: {:__block__, [], [{:{}, [line: 1], [:loop_item, nil, []]}]}]
                ]}
             ] = build_ast(tags)
    end

    test "a nested for block binds its own item" do
      tags = [
        {:block_start, {"for", "{ group <- @groups}"}},
        {:block_start, {"for", "{ item <- group.items}"}},
        {:text, "abc"},
        {:block_end, "for"},
        {:block_end, "for"}
      ]

      assert [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [{:=, [line: 1], [{:group, [line: 1], nil}, _outer_var]}, _groups]},
                  [
                    do:
                      {:__block__, [],
                       [
                         {:{}, [line: 1],
                          [
                            :loop_item,
                            outer_item,
                            [
                              {:for, [line: 1],
                               [
                                 {:<-, [line: 1],
                                  [{:=, [line: 1], [{:item, [line: 1], nil}, _inner_var]}, _items]},
                                 [do: {:__block__, [], [inner_loop_item]}]
                               ]}
                            ]
                          ]}
                       ]}
                  ]
                ]}
             ] = build_ast(tags)

      assert outer_item == {:{}, [line: 1], [loop_item_var()]}
      assert inner_loop_item == loop_item(text: "abc")
    end
  end

  describe "build_ast/1, $key attribute" do
    # The nodes of the one loop item a single for block's body compiles to.
    defp loop_body(tags) do
      assert [{:for, [line: 1], [_generator, [do: {:__block__, [], [loop_item]}]]}] =
               build_ast(tags)

      {:{}, [line: 1], [:loop_item, _source, nodes]} = loop_item
      nodes
    end

    defp item_expression, do: {:{}, [line: 1], [{:item, [line: 1], nil}]}

    # The attributes of every element with the given tag name, wherever it sits in the AST.
    defp element_attrs(ast, tag_name) do
      {_ast, attrs} =
        Macro.prewalk(ast, [], fn
          {:{}, _meta, [:element, ^tag_name, attrs, _children]} = node, acc ->
            {node, [attrs | acc]}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(attrs)
    end

    defp merged_key(tags, index, expression) do
      {"$key", [text: "#{template_hash(tags)}:#{index}", expression: expression]}
    end

    defp in_for(tags) do
      Enum.concat([[{:block_start, {"for", "{ item <- @items}"}}], tags, [{:block_end, "for"}]])
    end

    test "on an element, follows the key of the element's place" do
      # {%for item <- @items}<li $key={item}></li>{/for}
      tags = in_for([{:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}}])

      assert loop_body(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "li",
                  [{"$key", [text: "#{template_hash(tags)}:0", expression: item_expression()]}],
                  []
                ]}
             ]
    end

    test "on an element, trails the other attributes" do
      # {%for item <- @items}<li $key={item} class="a"></li>{/for}
      tags =
        in_for([
          {:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}, {"class", [text: "a"]}]}}
        ])

      assert [{:{}, [line: 1], [:element, "li", attrs, []]}] = loop_body(tags)

      assert attrs == [
               {"class", [text: "a"]},
               {"$key", [text: "#{template_hash(tags)}:0", expression: item_expression()]}
             ]
    end

    test "on a dynamic tag, follows the key of the tag's place" do
      # {%for item <- @items}<{@tag} $key={item} />{/for}
      tags =
        in_for([
          {:self_closing_tag, {{:expression, "{@tag}"}, [{"$key", [expression: "{item}"]}]}}
        ])

      assert [{:{}, [line: 1], [:dynamic_tag, _tag, attrs, []]}] = loop_body(tags)

      assert attrs == [
               {"$key", [text: "#{template_hash(tags)}:0", expression: item_expression()]}
             ]
    end

    test "on a component, stays as a prop" do
      # {%for item <- @items}<Card $key={item} />{/for}
      tags = in_for([{:self_closing_tag, {"Card", [{"$key", [expression: "{item}"]}]}}])

      assert [{:{}, [line: 1], [:component, _module, props, []]}] = loop_body(tags)
      assert props == [{"$key", [expression: item_expression()]}]
    end

    test "inside an if block in a for block's body" do
      # {%for item <- @items}{%if true}<li $key={item}></li>{/if}{/for}
      tags =
        in_for([
          {:block_start, {"if", "{ true}"}},
          {:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}},
          {:block_end, "if"}
        ])

      assert element_attrs(build_ast(tags), "li") == [[merged_key(tags, 0, item_expression())]]
    end

    test "inside an else block in a for block's body" do
      # {%for item <- @items}{%if true}a{%else}<li $key={item}></li>{/if}{/for}
      tags =
        in_for([
          {:block_start, {"if", "{ true}"}},
          {:text, "a"},
          {:block_start, "else"},
          {:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}},
          {:block_end, "if"}
        ])

      assert element_attrs(build_ast(tags), "li") == [[merged_key(tags, 0, item_expression())]]
    end

    test "on a tag directly inside a nested for block" do
      # {%for item <- @items}{%for x <- item.xs}<li $key={x}></li>{/for}{/for}
      tags =
        in_for([
          {:block_start, {"for", "{ x <- item.xs}"}},
          {:self_closing_tag, {"li", [{"$key", [expression: "{x}"]}]}},
          {:block_end, "for"}
        ])

      x_expression = {:{}, [line: 1], [{:x, [line: 1], nil}]}

      assert element_attrs(build_ast(tags), "li") == [[merged_key(tags, 0, x_expression)]]
    end

    test "after a closed sibling tag" do
      # {%for item <- @items}<span></span><li $key={item}></li>{/for}
      tags =
        in_for([
          {:start_tag, {"span", []}},
          {:end_tag, "span"},
          {:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}}
        ])

      assert element_attrs(build_ast(tags), "li") == [[merged_key(tags, 1, item_expression())]]
    end

    test "after a comment in a for block's body" do
      tags = Parser.parse_markup("{%for item <- @items}<!-- c --><li $key={item}></li>{/for}")

      assert element_attrs(build_ast(tags), "li") == [[merged_key(tags, 0, item_expression())]]
    end

    test "after a raw block in a for block's body" do
      tags =
        Parser.parse_markup("{%for item <- @items}{%raw}<b></b>{/raw}<li $key={item}></li>{/for}")

      # The tag inside the raw block is an element the template renders, so it takes index 0.
      assert element_attrs(build_ast(tags), "li") == [[merged_key(tags, 1, item_expression())]]
    end

    test "a binding sharing the prefix is not a $key" do
      # <input $key_down="go" />
      tags = [{:self_closing_tag, {"input", [{"$key_down", [text: "go"]}]}}]

      assert [{:{}, [line: 1], [:element, "input", [{"$key_down", [text: "go"]}, _key], []]}] =
               build_ast(tags)
    end

    test "raises outside a for block" do
      # <li $key={item}></li>
      tags = [{:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}}]

      assert_raise Hologram.TemplateSyntaxError,
                   "$key goes on a tag directly inside a {%for} block",
                   fn -> build_ast(tags) end
    end

    test "raises on a tag nested in an element of a for block's body" do
      # {%for item <- @items}<ul><li $key={item}></li></ul>{/for}
      tags =
        in_for([
          {:start_tag, {"ul", []}},
          {:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}},
          {:end_tag, "ul"}
        ])

      assert_raise Hologram.TemplateSyntaxError,
                   "$key goes on a tag directly inside a {%for} block",
                   fn -> build_ast(tags) end
    end

    test "raises on a tag in a component's children in a for block's body" do
      # {%for item <- @items}<Card><li $key={item}></li></Card>{/for}
      tags =
        in_for([
          {:start_tag, {"Card", []}},
          {:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}},
          {:end_tag, "Card"}
        ])

      assert_raise Hologram.TemplateSyntaxError,
                   "$key goes on a tag directly inside a {%for} block",
                   fn -> build_ast(tags) end
    end

    test "raises after the for block ends" do
      # {%for item <- @items}a{/for}<li $key={item}></li>
      tags =
        [{:text, "a"}]
        |> in_for()
        |> Enum.concat([{:self_closing_tag, {"li", [{"$key", [expression: "{item}"]}]}}])

      assert_raise Hologram.TemplateSyntaxError,
                   "$key goes on a tag directly inside a {%for} block",
                   fn -> build_ast(tags) end
    end

    test "raises on a tag a key would name nothing new on" do
      for tag_name <- ["document", "slot", "window"] do
        # e.g. {%for item <- @items}<slot $key={item} />{/for}
        tags = in_for([{:self_closing_tag, {tag_name, [{"$key", [expression: "{item}"]}]}}])

        assert_raise Hologram.TemplateSyntaxError,
                     "$key can't go on a <#{tag_name}> tag",
                     fn -> build_ast(tags) end
      end

      for tag_name <- ["body", "head", "html"] do
        # e.g. {%for item <- @items}<body $key={item}></body>{/for}
        tags =
          in_for([
            {:start_tag, {tag_name, [{"$key", [expression: "{item}"]}]}},
            {:end_tag, tag_name}
          ])

        assert_raise Hologram.TemplateSyntaxError,
                     "$key can't go on a <#{tag_name}> tag",
                     fn -> build_ast(tags) end
      end
    end

    test "raises on a component with a literal cid" do
      # {%for item <- @items}<Card cid="card" $key={item} />{/for}
      tags =
        in_for([
          {:self_closing_tag,
           {"Card", [{"cid", [text: "card"]}, {"$key", [expression: "{item}"]}]}}
        ])

      assert_raise Hologram.TemplateSyntaxError,
                   "a stateful component is keyed by its cid, so it can't take $key",
                   fn -> build_ast(tags) end
    end

    test "raises for a modifier" do
      # {%for item <- @items}<li $key.once={item}></li>{/for}
      tags = in_for([{:self_closing_tag, {"li", [{"$key.once", [expression: "{item}"]}]}}])

      assert_raise Hologram.TemplateSyntaxError,
                   ~s'the $key attribute takes no modifiers, got "once"',
                   fn -> build_ast(tags) end
    end

    test "raises for a missing value, a text value and a mixed value" do
      for value_parts <- [[], [text: "a"], [text: "a", expression: "{item}"]] do
        # {%for item <- @items}<li $key="a"></li>{/for}
        tags = in_for([{:self_closing_tag, {"li", [{"$key", value_parts}]}}])

        assert_raise Hologram.TemplateSyntaxError,
                     "the $key attribute takes a single expression, like $key={item.slug}",
                     fn -> build_ast(tags) end
      end
    end

    test "raises for a quoted expression, as $focused does" do
      tags = Parser.parse_markup(~s'{%for item <- @items}<li $key="{item}"></li>{/for}')

      assert_raise Hologram.TemplateSyntaxError,
                   "the $key attribute takes a single expression, like $key={item.slug}",
                   fn -> build_ast(tags) end
    end

    test "raises for two $key attributes" do
      # {%for item <- @items}<li $key={item} $key={item}></li>{/for}
      tags =
        in_for([
          {:self_closing_tag,
           {"li", [{"$key", [expression: "{item}"]}, {"$key", [expression: "{item}"]}]}}
        ])

      assert_raise Hologram.TemplateSyntaxError,
                   "a tag takes one $key attribute",
                   fn -> build_ast(tags) end
    end
  end

  describe "build_ast/1, if block" do
    test "with one child" do
      # {%if @xyz == 123}abc{/if}
      tags = [{:block_start, {"if", "{ @xyz == 123}"}}, {:text, "abc"}, {:block_end, "if"}]

      assert build_ast(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1],
                   [
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :xyz]},
                      [no_parens: true, line: 1], []},
                     123
                   ]},
                  [do: [text: "abc"]]
                ]}
             ]
    end

    test "with multiple children" do
      # {%if @xyz == 123}abc<div></div>{/if}
      tags = [
        {:block_start, {"if", "{ @xyz == 123}"}},
        {:text, "abc"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        {:block_end, "if"}
      ]

      assert build_ast(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1],
                   [
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :xyz]},
                      [no_parens: true, line: 1], []},
                     123
                   ]},
                  [
                    do: [{:text, "abc"}, {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}]
                  ]
                ]}
             ]
    end

    test "with else subblock having single child" do
      # {%if @xyz == 123}aaa{%else}bbb{/if}
      tags = [
        {:block_start, {"if", "{ @xyz == 123}"}},
        {:text, "aaa"},
        {:block_start, "else"},
        {:text, "bbb"},
        {:block_end, "if"}
      ]

      assert build_ast(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1],
                   [
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :xyz]},
                      [no_parens: true, line: 1], []},
                     123
                   ]},
                  [do: [{:text, "aaa"}], else: [{:text, "bbb"}]]
                ]}
             ]
    end

    test "with else subblock having multiple children" do
      # {%if @xyz == 123}aaa{%else}bbb<div></div>{/if}
      tags = [
        {:block_start, {"if", "{ @xyz == 123}"}},
        {:text, "aaa"},
        {:block_start, "else"},
        {:text, "bbb"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        {:block_end, "if"}
      ]

      assert build_ast(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1],
                   [
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :xyz]},
                      [no_parens: true, line: 1], []},
                     123
                   ]},
                  [
                    do: [{:text, "aaa"}],
                    else: [
                      {:text, "bbb"},
                      {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}
                    ]
                  ]
                ]}
             ]
    end

    test "nested in element node, as the only child" do
      # <div>{%if @aaa == 123}bbb{/if}</div>
      tags = [
        start_tag: {"div", []},
        block_start: {"if", "{ @aaa == 123}"},
        text: "bbb",
        block_end: "if",
        end_tag: "div"
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [key(tags, 0)],
                  [
                    {:if, [line: 1],
                     [
                       {:==, [line: 1],
                        [
                          {{:., [line: 1], [{:vars, [line: 1], nil}, :aaa]},
                           [no_parens: true, line: 1], []},
                          123
                        ]},
                       [do: [text: "bbb"]]
                     ]}
                  ]
                ]}
             ]
    end

    test "nested in component node, as the only child" do
      # <MyComponent>{%if @aaa == 123}bbb{/if}</MyComponent>
      tags = [
        start_tag: {"MyComponent", []},
        block_start: {"if", "{ @aaa == 123}"},
        text: "bbb",
        block_end: "if",
        end_tag: "MyComponent"
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  [
                    {:if, [line: 1],
                     [
                       {:==, [line: 1],
                        [
                          {{:., [line: 1], [{:vars, [line: 1], nil}, :aaa]},
                           [no_parens: true, line: 1], []},
                          123
                        ]},
                       [do: [text: "bbb"]]
                     ]}
                  ]
                ]}
             ]
    end

    test "nested in element node, as the first child of many" do
      # <div>{%if @aaa == 123}bbb{/if}ccc</div>
      tags = [
        start_tag: {"div", []},
        block_start: {"if", "{ @aaa == 123}"},
        text: "bbb",
        block_end: "if",
        text: "ccc",
        end_tag: "div"
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [key(tags, 0)],
                  [
                    {:if, [line: 1],
                     [
                       {:==, [line: 1],
                        [
                          {{:., [line: 1], [{:vars, [line: 1], nil}, :aaa]},
                           [no_parens: true, line: 1], []},
                          123
                        ]},
                       [do: [text: "bbb"]]
                     ]},
                    {:text, "ccc"}
                  ]
                ]}
             ]
    end

    test "nested in component node, as the first child of many" do
      # <MyComponent>{%if @aaa == 123}bbb{/if}ccc</MyComponent>
      tags = [
        start_tag: {"MyComponent", []},
        block_start: {"if", "{ @aaa == 123}"},
        text: "bbb",
        block_end: "if",
        text: "ccc",
        end_tag: "MyComponent"
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  [
                    {:if, [line: 1],
                     [
                       {:==, [line: 1],
                        [
                          {{:., [line: 1], [{:vars, [line: 1], nil}, :aaa]},
                           [no_parens: true, line: 1], []},
                          123
                        ]},
                       [do: [text: "bbb"]]
                     ]},
                    {:text, "ccc"}
                  ]
                ]}
             ]
    end

    test "nested in element node, as the last child of many" do
      # <div>ccc{%if @aaa == 123}bbb{/if}</div>
      tags = [
        start_tag: {"div", []},
        text: "ccc",
        block_start: {"if", "{ @aaa == 123}"},
        text: "bbb",
        block_end: "if",
        end_tag: "div"
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :element,
                  "div",
                  [key(tags, 0)],
                  [
                    {:text, "ccc"},
                    {:if, [line: 1],
                     [
                       {:==, [line: 1],
                        [
                          {{:., [line: 1], [{:vars, [line: 1], nil}, :aaa]},
                           [no_parens: true, line: 1], []},
                          123
                        ]},
                       [do: [text: "bbb"]]
                     ]}
                  ]
                ]}
             ]
    end

    test "nested in component node, as the last child of many" do
      # <MyComponent>ccc{%if @aaa == 123}bbb{/if}</MyComponent>
      tags = [
        start_tag: {"MyComponent", []},
        text: "ccc",
        block_start: {"if", "{ @aaa == 123}"},
        text: "bbb",
        block_end: "if",
        end_tag: "MyComponent"
      ]

      assert build_ast(tags) == [
               {:{}, [line: 1],
                [
                  :component,
                  {:alias!, [line: 1], [{:__aliases__, [line: 1], [:MyComponent]}]},
                  [],
                  [
                    {:text, "ccc"},
                    {:if, [line: 1],
                     [
                       {:==, [line: 1],
                        [
                          {{:., [line: 1], [{:vars, [line: 1], nil}, :aaa]},
                           [no_parens: true, line: 1], []},
                          123
                        ]},
                       [do: [text: "bbb"]]
                     ]}
                  ]
                ]}
             ]
    end
  end

  describe "build_ast/1, keys" do
    test "do not depend on line endings" do
      # <div>bbb
      # ccc</div>, checked out with Unix and with Windows line endings
      lf_tags = [{:start_tag, {"div", []}}, {:text, "bbb\nccc"}, {:end_tag, "div"}]
      crlf_tags = [{:start_tag, {"div", []}}, {:text, "bbb\r\nccc"}, {:end_tag, "div"}]

      assert keys(build_ast(lf_tags)) == keys(build_ast(crlf_tags))
    end
  end

  describe "build_ast/1, raw block" do
    test "empty raw block renders nothing" do
      parse = [
        {:block_start, "raw"},
        {:block_end, "raw"}
      ]

      assert build_ast(parse) == []
    end

    test "preserves text inside raw block as separate text nodes without merging" do
      parse = [
        {:text, "before"},
        {:block_start, "raw"},
        {:text, "during"},
        {:block_end, "raw"},
        {:text, "after"}
      ]

      assert build_ast(parse) == [{:text, "before"}, {:text, "during"}, {:text, "after"}]
    end

    test "literal string \"raw\" as text content does not interfere with raw block processing" do
      parse = [
        {:text, "raw"},
        {:block_start, "raw"},
        {:text, "raw"},
        {:block_end, "raw"},
        {:text, "raw"}
      ]

      assert build_ast(parse) == [{:text, "raw"}, {:text, "raw"}, {:text, "raw"}]
    end
  end

  describe "build_ast/1, substitute module attributes" do
    test "non-nested list" do
      tags = [{:expression, "{[1, @a, 2, @b]}"}]

      assert build_ast(tags) == [
               {
                 :expression,
                 {:{}, [line: 1],
                  [
                    [
                      1,
                      {{:., [line: 1], [{:vars, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      2,
                      {{:., [line: 1], [{:vars, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                       []}
                    ]
                  ]}
               }
             ]
    end

    test "nested list" do
      tags = [{:expression, "{[1, @a, [2, @b, 3, @c]]}"}]

      assert build_ast(tags) == [
               {
                 :expression,
                 {:{}, [line: 1],
                  [
                    [
                      1,
                      {{:., [line: 1], [{:vars, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      [
                        2,
                        {{:., [line: 1], [{:vars, [line: 1], nil}, :b]},
                         [no_parens: true, line: 1], []},
                        3,
                        {{:., [line: 1], [{:vars, [line: 1], nil}, :c]},
                         [no_parens: true, line: 1], []}
                      ]
                    ]
                  ]}
               }
             ]
    end

    test "non-nested 2-element tuple" do
      tags = [{:expression, "{{@a, @b}}"}]

      assert build_ast(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {{{:., [line: 1], [{:vars, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                     []},
                    {{:., [line: 1], [{:vars, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                     []}}
                 ]}}
             ]
    end

    test "nested 2-element tuple" do
      tags = [{:expression, "{{1, {@a, @b}}}"}]

      assert build_ast(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {1,
                    {{{:., [line: 1], [{:vars, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                      []},
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                      []}}}
                 ]}}
             ]
    end

    test "non-nested 4-element tuple" do
      tags = [{:expression, "{{1, @a, 2, @b}}"}]

      assert build_ast(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {:{}, [line: 1],
                    [
                      1,
                      {{:., [line: 1], [{:vars, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      2,
                      {{:., [line: 1], [{:vars, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                       []}
                    ]}
                 ]}}
             ]
    end

    test "nested 4-element tuple" do
      tags = [{:expression, "{{1, @a, {2, @b, 3, @c}, 4}}"}]

      assert build_ast(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {:{}, [line: 1],
                    [
                      1,
                      {{:., [line: 1], [{:vars, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      {:{}, [line: 1],
                       [
                         2,
                         {{:., [line: 1], [{:vars, [line: 1], nil}, :b]},
                          [no_parens: true, line: 1], []},
                         3,
                         {{:., [line: 1], [{:vars, [line: 1], nil}, :c]},
                          [no_parens: true, line: 1], []}
                       ]},
                      4
                    ]}
                 ]}}
             ]
    end
  end

  test "build_ast/1, nested AST" do
    tags = [{:expression, "{(fn x -> [x | @acc] end).(@value)}"}]

    assert build_ast(tags) == [
             {
               :expression,
               {:{}, [line: 1],
                [
                  {{:., [line: 1],
                    [
                      {:fn, [line: 1],
                       [
                         {:->, [line: 1],
                          [
                            [{:x, [line: 1], nil}],
                            {:__block__, [],
                             [
                               [
                                 {:|, [line: 1],
                                  [
                                    {:x, [line: 1], nil},
                                    {{:., [line: 1], [{:vars, [line: 1], nil}, :acc]},
                                     [no_parens: true, line: 1], []}
                                  ]}
                               ]
                             ]}
                          ]}
                       ]}
                    ]}, [line: 1],
                   [
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :value]},
                      [no_parens: true, line: 1], []}
                   ]}
                ]}
             }
           ]
  end

  defp keys(ast) do
    ast
    |> inspect(limit: :infinity)
    |> then(&Regex.scan(~r/"\$key", \[text: "([a-z0-9]+:\d+)"\]/, &1))
    |> Enum.map(&List.last/1)
  end
end
