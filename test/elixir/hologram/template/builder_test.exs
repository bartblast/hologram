defmodule Hologram.Template.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Builder

  test "text node" do
    assert build([{:text, "abc"}]) == [{:text, "abc"}]
  end

  describe "element node & component node" do
    nodes = [
      {:element, "attribute", "div"},
      {:component, "property", "Aaa.Bbb"}
    ]

    Enum.each(nodes, fn {tag_type, attr_or_prop, tag_name} ->
      test "#{tag_type} node without #{attr_or_prop}(s) or children" do
        tag_name = unquote(tag_name)
        tags = [{:start_tag, {tag_name, []}}, {:end_tag, tag_name}]

        assert build(tags) == [
                 {:{}, [line: 1], [unquote(tag_type), tag_name, [], []]}
               ]
      end

      test "#{tag_type} node with single #{attr_or_prop}" do
        tag_name = unquote(tag_name)
        tags = [{:start_tag, {tag_name, [{"my_key", [text: "my_value"]}]}}, {:end_tag, tag_name}]

        assert build(tags) ==
                 [
                   {:{}, [line: 1],
                    [unquote(tag_type), tag_name, [{"my_key", [text: "my_value"]}], []]}
                 ]
      end

      test "#{tag_type} node, with multiple #{attr_or_prop}(s)" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag,
           {tag_name, [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}]}},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [text: "my_value_2"]}],
                    []
                  ]}
               ]
      end

      test "#{tag_type} node #{attr_or_prop} with multiple value parts" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, [{"my_key", [text: "my_value_1", text: "my_value_2"]}]}},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [{"my_key", [text: "my_value_1", text: "my_value_2"]}],
                    []
                  ]}
               ]
      end

      test "#{tag_type} node with text child" do
        tag_name = unquote(tag_name)
        tags = [{:start_tag, {tag_name, []}}, {:text, "abc"}, {:end_tag, tag_name}]

        assert build(tags) == [
                 {:{}, [line: 1], [unquote(tag_type), tag_name, [], [{:text, "abc"}]]}
               ]
      end

      test "#{tag_type} node with element child" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, []}},
          {:start_tag, {"span", []}},
          {:end_tag, "span"},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [],
                    [{:{}, [line: 1], [:element, "span", [], []]}]
                  ]}
               ]
      end

      test "#{tag_type} node with component child" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, []}},
          {:start_tag, {"Xxx.Yyy", []}},
          {:end_tag, "Xxx.Yyy"},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [],
                    [{:{}, [line: 1], [:component, "Xxx.Yyy", [], []]}]
                  ]}
               ]
      end

      test "#{tag_type} node with multiple children" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, []}},
          {:start_tag, {"span", []}},
          {:end_tag, "span"},
          {:text, "abc"},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [],
                    [{:{}, [line: 1], [:element, "span", [], []]}, {:text, "abc"}]
                  ]}
               ]
      end
    end)
  end

  describe "expression node" do
    test "in text" do
      tags = [{:text, "abc"}, {:expression, "{1 + 2}"}, {:text, "xyz"}]
      assert build(tags) == [text: "abc", expression: {:+, [line: 1], [1, 2]}, text: "xyz"]
    end

    nodes = [
      {:element, "attribute", "div"},
      {:component, "property", "Aaa.Bbb"}
    ]

    Enum.each(nodes, fn {tag_type, attr_or_prop, tag_name} ->
      test "in #{tag_type} #{attr_or_prop} value, with one part only" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, [{"my_key", [expression: "{1 + 2}"]}]}},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [{"my_key", [expression: {:+, [line: 1], [1, 2]}]}],
                    []
                  ]}
               ]
      end

      test "in #{tag_type} #{attr_or_prop} value, after text part" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, [{"my_key", [text: "my_value", expression: "{1 + 2}"]}]}},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [{"my_key", [text: "my_value", expression: {:+, [line: 1], [1, 2]}]}],
                    []
                  ]}
               ]
      end

      test "in #{tag_type} #{attr_or_prop} value, before text part" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag, {tag_name, [{"my_key", [expression: "{1 + 2}", text: "my_value"]}]}},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [{"my_key", [expression: {:+, [line: 1], [1, 2]}, text: "my_value"]}],
                    []
                  ]}
               ]
      end

      test "in #{tag_type} #{attr_or_prop} value, after another expression part" do
        tag_name = unquote(tag_name)

        tags = [
          {:start_tag,
           {tag_name, [{"my_key", [expression: "{1 + 2}", expression: "{@my_var * 9}"]}]}},
          {:end_tag, tag_name}
        ]

        assert build(tags) == [
                 {:{}, [line: 1],
                  [
                    unquote(tag_type),
                    tag_name,
                    [
                      {"my_key",
                       [
                         expression: {:+, [line: 1], [1, 2]},
                         expression:
                           {:*, [line: 1], [{:@, [line: 1], [{:my_var, [line: 1], nil}]}, 9]}
                       ]}
                    ],
                    []
                  ]}
               ]
      end
    end)
  end

  describe "for block" do
    test "with one child" do
      tags = [{:block_start, {"for", "{ item <- @items}"}}, {:text, "abc"}, {:block_end, "for"}]

      assert build(tags) == [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [{:item, [line: 1], nil}, {:@, [line: 1], [{:items, [line: 1], nil}]}]},
                  [do: {:__block__, [], [[{:text, "abc"}]]}]
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

      assert build(tags) == [
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [{:item, [line: 1], nil}, {:@, [line: 1], [{:items, [line: 1], nil}]}]},
                  [
                    do:
                      {:__block__, [],
                       [[{:text, "abc"}, {:{}, [line: 1], [:element, "div", [], []]}]]}
                  ]
                ]}
             ]
    end
  end

  describe "if block" do
    test "with one child" do
      tags = [{:block_start, {"if", "{ @xyz == 123}"}}, {:text, "abc"}, {:block_end, "if"}]

      assert build(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1], [{:@, [line: 1], [{:xyz, [line: 1], nil}]}, 123]},
                  [do: {:__block__, [], [[{:text, "abc"}]]}]
                ]}
             ]
    end

    test "with multiple children" do
      tags = [
        {:block_start, {"if", "{ @xyz == 123}"}},
        {:text, "abc"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        {:block_end, "if"}
      ]

      assert build(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1], [{:@, [line: 1], [{:xyz, [line: 1], nil}]}, 123]},
                  [
                    do:
                      {:__block__, [],
                       [[{:text, "abc"}, {:{}, [line: 1], [:element, "div", [], []]}]]}
                  ]
                ]}
             ]
    end

    test "with else subblock having single child" do
      tags = [
        {:block_start, {"if", "{ @xyz == 123}"}},
        {:text, "aaa"},
        {:block_start, "else"},
        {:text, "bbb"},
        {:block_end, "if"}
      ]

      assert build(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1], [{:@, [line: 1], [{:xyz, [line: 1], nil}]}, 123]},
                  [do: [{:text, "aaa"}], else: [{:text, "bbb"}]]
                ]}
             ]
    end

    test "with else subblock having multiple children" do
      tags = [
        {:block_start, {"if", "{ @xyz == 123}"}},
        {:text, "aaa"},
        {:block_start, "else"},
        {:text, "bbb"},
        {:start_tag, {"div", []}},
        {:end_tag, "div"},
        {:block_end, "if"}
      ]

      assert build(tags) == [
               {:if, [line: 1],
                [
                  {:==, [line: 1], [{:@, [line: 1], [{:xyz, [line: 1], nil}]}, 123]},
                  [
                    do: [{:text, "aaa"}],
                    else: [{:text, "bbb"}, {:{}, [line: 1], [:element, "div", [], []]}]
                  ]
                ]}
             ]
    end
  end

  describe "substitute module attributes" do
    test "non-nested list" do
      tags = [{:expression, "{[1, @a, 2, @b]}"}]

      assert build(tags) == [
               {
                 :expression,
                 {:{}, [line: 1],
                  [
                    [
                      1,
                      {{:., [line: 1], [{:data, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      2,
                      {{:., [line: 1], [{:data, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                       []}
                    ]
                  ]}
               }
             ]
    end

    test "nested list" do
      tags = [{:expression, "{[1, @a, [2, @b, 3, @c]]}"}]

      assert build(tags) == [
               {
                 :expression,
                 {:{}, [line: 1],
                  [
                    [
                      1,
                      {{:., [line: 1], [{:data, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      [
                        2,
                        {{:., [line: 1], [{:data, [line: 1], nil}, :b]},
                         [no_parens: true, line: 1], []},
                        3,
                        {{:., [line: 1], [{:data, [line: 1], nil}, :c]},
                         [no_parens: true, line: 1], []}
                      ]
                    ]
                  ]}
               }
             ]
    end

    test "non-nested 2-element tuple" do
      tags = [{:expression, "{{@a, @b}}"}]

      assert build(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {{{:., [line: 1], [{:data, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                     []},
                    {{:., [line: 1], [{:data, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                     []}}
                 ]}}
             ]
    end

    test "nested 2-element tuple" do
      tags = [{:expression, "{{1, {@a, @b}}}"}]

      assert build(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {1,
                    {{{:., [line: 1], [{:data, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                      []},
                     {{:., [line: 1], [{:data, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                      []}}}
                 ]}}
             ]
    end

    test "non-nested 4-element tuple" do
      tags = [{:expression, "{{1, @a, 2, @b}}"}]

      assert build(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {:{}, [line: 1],
                    [
                      1,
                      {{:., [line: 1], [{:data, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      2,
                      {{:., [line: 1], [{:data, [line: 1], nil}, :b]}, [no_parens: true, line: 1],
                       []}
                    ]}
                 ]}}
             ]
    end

    test "nested 4-element tuple" do
      tags = [{:expression, "{{1, @a, {2, @b, 3, @c}, 4}}"}]

      assert build(tags) == [
               {:expression,
                {:{}, [line: 1],
                 [
                   {:{}, [line: 1],
                    [
                      1,
                      {{:., [line: 1], [{:data, [line: 1], nil}, :a]}, [no_parens: true, line: 1],
                       []},
                      {:{}, [line: 1],
                       [
                         2,
                         {{:., [line: 1], [{:data, [line: 1], nil}, :b]},
                          [no_parens: true, line: 1], []},
                         3,
                         {{:., [line: 1], [{:data, [line: 1], nil}, :c]},
                          [no_parens: true, line: 1], []}
                       ]},
                      4
                    ]}
                 ]}}
             ]
    end
  end

  test "nested AST" do
    tags = [{:expression, "{(fn x -> [x | @acc] end).(@value)}"}]

    assert build(tags) == [
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
                            [
                              {:|, [line: 1],
                               [
                                 {:x, [line: 1], nil},
                                 {{:., [line: 1], [{:data, [line: 1], nil}, :acc]},
                                  [no_parens: true, line: 1], []}
                               ]}
                            ]
                          ]}
                       ]}
                    ]}, [line: 1],
                   [
                     {{:., [line: 1], [{:data, [line: 1], nil}, :value]},
                      [no_parens: true, line: 1], []}
                   ]}
                ]}
             }
           ]
  end
end
