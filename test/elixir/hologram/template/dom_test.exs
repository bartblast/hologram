defmodule Hologram.Template.DOMTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.DOM

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
    test "with one child" do
      tags = [{:block_start, {"for", "{ item <- @items}"}}, {:text, "abc"}, {:block_end, "for"}]

      assert build_ast(tags) == [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:item, [line: 1], nil},
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :items]},
                      [no_parens: true, line: 1], []}
                   ]},
                  [do: {:__block__, [], [[text: "abc"]]}]
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
                   [
                     {:item, [line: 1], nil},
                     {{:., [line: 1], [{:vars, [line: 1], nil}, :items]},
                      [no_parens: true, line: 1], []}
                   ]},
                  [
                    do:
                      {:__block__, [],
                       [[{:text, "abc"}, {:{}, [line: 1], [:element, "div", [key(tags, 0)], []]}]]}
                  ]
                ]}
             ]
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
