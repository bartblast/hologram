defmodule Hologram.Template.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Builder

  test "text node" do
    assert build([{:text, "abc"}]) == [{:text, "abc"}]
  end

  describe "element node & component node" do
    [
      {:element, "attribute", "div"},
      {:component, "property", "Aaa.Bbb"}
    ]
    |> Enum.each(fn {tag_type, attr_or_prop, tag_name} ->
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
end
