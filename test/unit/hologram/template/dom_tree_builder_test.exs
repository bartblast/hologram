defmodule Hologram.Template.DOMTreeBuilderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.DOMTreeBuilder
  alias Hologram.Template.SyntaxError

  test "text node" do
    tags = [text: "abc"]

    result = DOMTreeBuilder.build(tags)
    expected = [text: "abc"]

    assert result == expected
  end

  test "expression node" do
    tags = [expression: "{@test}"]
    result = DOMTreeBuilder.build(tags)
    expected = [expression: "{@test}"]

    assert result == expected
  end

  test "element node" do
    tags = [start_tag: {"div", []}, end_tag: "div"]

    result = DOMTreeBuilder.build(tags)
    expected = [{:element, "div", [], []}]

    assert result == expected
  end

  test "component node" do
    tags = [start_tag: {"Abc.Bcd", []}, end_tag: "Abc.Bcd"]

    result = DOMTreeBuilder.build(tags)
    expected = [{:component, "Abc.Bcd", [], []}]

    assert result == expected
  end

  test "self-closing element node" do
    tags = [self_closing_tag: {"br", []}]

    result = DOMTreeBuilder.build(tags)
    expected = [{:element, "br", [], []}]

    assert result == expected
  end

  test "self-closing component node" do
    tags = [self_closing_tag: {"Abc.Bcd", []}]

    result = DOMTreeBuilder.build(tags)
    expected = [{:component, "Abc.Bcd", [], []}]

    assert result == expected
  end

  test "unclosed element node" do
    tags = [start_tag: {"div", []}]

    assert_raise SyntaxError, "div tag is unclosed", fn ->
      DOMTreeBuilder.build(tags)
    end
  end

  test "unclosed component node" do
    tags = [start_tag: {"Abc.Bcd", []}]

    assert_raise SyntaxError, "Abc.Bcd tag is unclosed", fn ->
      DOMTreeBuilder.build(tags)
    end
  end

  test "multiple nodes" do
    tags = [
      start_tag: {"div", []},
      end_tag: "div",
      text: "abc",
      self_closing_tag: {"Abc.Bcd", []}
    ]

    result = DOMTreeBuilder.build(tags)
    expected = [{:element, "div", [], []}, {:text, "abc"}, {:component, "Abc.Bcd", [], []}]

    assert result == expected
  end

  test "nested nodes" do
    tags = [
      start_tag: {"div", []},
      start_tag: {"span", []},
      start_tag: {"Abc.Bcd", []},
      text: "abc",
      end_tag: "Abc.Bcd",
      end_tag: "span",
      end_tag: "div"
    ]

    result = DOMTreeBuilder.build(tags)

    expected = [
      {:element, "div", [],
       [
         {:element, "span", [],
          [
            {:component, "Abc.Bcd", [], [text: "abc"]}
          ]}
       ]}
    ]

    assert result == expected
  end

  test "element node attributes" do
    tags = [
      start_tag: {"div", [{"id", [literal: "abc", expression: "{@test}", literal: "xyz"]}]},
      end_tag: "div"
    ]

    result = DOMTreeBuilder.build(tags)

    expected = [
      {:element, "div", [{"id", [literal: "abc", expression: "{@test}", literal: "xyz"]}], []}
    ]

    assert result == expected
  end

  test "component node props" do
    tags = [
      start_tag: {"Abc.Bcd", [{"id", [literal: "abc", expression: "{@test}", literal: "xyz"]}]},
      end_tag: "Abc.Bcd"
    ]

    result = DOMTreeBuilder.build(tags)

    expected = [
      {:component, "Abc.Bcd", [{"id", [literal: "abc", expression: "{@test}", literal: "xyz"]}], []}
    ]

    assert result == expected
  end
end
