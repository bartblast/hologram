defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Parser
  alias Hologram.Template.SyntaxError

  test "parse template into a DOM tree" do
    markup = "<div><span id=\"test\">abc</span></div>"
    result = Parser.parse!(markup)

    expected = [
      {:element, "div", [],
       [{:element, "span", [{"id", [literal: "test"]}], [text: "abc"]}]}
    ]

    assert result == expected
  end

  test "remove doctype" do
    markup = "<!DoCtYpE html test_1 test_2>content"

    result = Parser.parse!(markup)
    expected = [{:text, "content"}]

    assert result == expected
  end

  test "remove comments" do
    special_chars = "abc \n \r \t < > / = \" { } ! -"
    markup = "aaa<!-- #{special_chars} -->bbb<!-- #{special_chars} -->ccc"

    result = Parser.parse!(markup)
    expected = [{:text, "aaabbbccc"}]

    assert result == expected
  end

  test "trim leading and trailing whitespaces" do
    markup = "\n\t content \t\n"

    result = Parser.parse!(markup)
    expected = [{:text, "content"}]

    assert result == expected
  end
end
