defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.{Parser, SyntaxError}

  defp assert_syntax_error(markup, message) do
    assert_raise SyntaxError, message, fn ->
      Parser.parse(markup)
    end
  end

  describe "template end handling" do
    test "text" do
      markup = "abc"

      result = Parser.parse(markup)
      expected = ["abc"]

      assert result == expected
    end

    test "start tag bracket" do
      markup = "abc<"
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "unfinished start tag" do
      markup = "<div"
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "attribute key" do
      markup = "<div class"
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "attribute assignment" do
      markup = "<div class="
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "attribute value double quoted" do
      markup = "<div class=\""
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "attribute value in braces" do
      markup = "<div class={"
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "end tag bracket" do
      markup = "<div></"
      assert_syntax_error(markup, "Unfinished tag")
    end

    test "unfinished end tag" do
      markup = "<div></div"
      assert_syntax_error(markup, "Unfinished tag")
    end
  end

  describe "whitespace handling" do
    test "whitespace inside text" do
      markup = "abc \n\r\txyz"

      result = Parser.parse(markup)
      expected = ["abc \n\r\txyz"]

      assert result == expected
    end

    test "whitespace after start tag bracket" do
      markup = "< div>"
      error = "Whitespace is not allowed between \"<\" and tag name"

      assert_syntax_error(markup, error)
    end

    test "whitespace inside start tag" do
      markup = "<div ></div>"

      result = Parser.parse(markup)
      expected = [{"div", [], []}]

      assert result == expected
    end

    test "whitespace after attribute key" do
      markup = "<div class ></div>"

      result = Parser.parse(markup)
      expected = [{"div", [{"class", "class"}], []}]

      assert result == expected
    end
  end
end
