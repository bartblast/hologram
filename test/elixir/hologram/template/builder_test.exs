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
end
