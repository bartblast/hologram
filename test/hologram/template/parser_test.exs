defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.{Parser, SyntaxError}

  defp assert_syntax_error(markup, message) do
    message = "\n#{message}" |> String.replace_trailing("\n", "")

    assert_raise SyntaxError, message, fn ->
      Parser.parse(markup)
    end
  end

  test "error message" do
    markup = "1234567890123456789012345< 1234567890123456789012345"

    message = """
    7890123456789012345< 12345678901234567890
                        ^
    """

    assert_syntax_error(markup, message)
  end

  describe "template end handling" do
    test "text tag" do
      markup = "abc"

      result = Parser.parse(markup)
      expected = ["abc"]

      assert result == expected
    end

    test "start tag bracket" do
      markup = "abc<"

      message = """
      abc<
          ^
      """

      assert_syntax_error(markup, message)
    end

    test "unfinished start tag" do
      markup = "<div"

      message = """
      <div
          ^
      """

      assert_syntax_error(markup, message)
    end

    test "attribute key" do
      markup = "<div class"

      message = """
      <div class
                ^
      """

      assert_syntax_error(markup, message)
    end

    test "attribute assignment" do
      markup = "<div class="

      message = """
      <div class=
                 ^
      """

      assert_syntax_error(markup, message)
    end

    test "attribute value double quoted" do
      markup = "<div class=\""

      message = """
      <div class="
                  ^
      """

      assert_syntax_error(markup, message)
    end

    test "attribute value in braces" do
      markup = "<div class={"

      message = """
      <div class={
                  ^
      """

      assert_syntax_error(markup, message)
    end

    test "end tag bracket" do
      markup = "<div></"

      message = """
      <div></
             ^
      """

      assert_syntax_error(markup, message)
    end

    test "unfinished end tag" do
      markup = "<div></div"

      message = """
      <div></div
                ^
      """

      assert_syntax_error(markup, message)
    end
  end

  describe "whitespace handling" do
    test "whitespace inside text tag" do
      markup = "abc \n\r\txyz"

      result = Parser.parse(markup)
      expected = ["abc \n\r\txyz"]

      assert result == expected
    end

    test "whitespace after start tag bracket" do
      markup = "< div>"

      message = """
      < div>
       ^
      """

      assert_syntax_error(markup, message)
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
      expected = [{"div", [{"class", ""}], []}]

      assert result == expected
    end

    test "whitespace after attribute assignment" do
      markup = "<div class= ></div>"

      message = """
      <div class= ></div>
                 ^
      """

      assert_syntax_error(markup, message)
    end

    test "whitespace inside double quoted attribute value" do
      markup = "<div class=\" \n\r\t\"></div>"

      result = Parser.parse(markup)
      expected = [{"div", [{"class", " \n\r\t"}], []}]

      assert result == expected
    end

    test "whitespace inside attribute value in braces" do
      markup = "<div class={ \n\r\t\}></div>"

      result = Parser.parse(markup)
      expected = [{"div", [{"class", "{ \n\r\t}"}], []}]

      assert result == expected
    end

    test "whitespace after end tag bracket" do
      markup = "</ div>"

      message = """
      </ div>
        ^
      """

      assert_syntax_error(markup, message)
    end

    test "whitespace inside end tag" do
      markup = "<div></div >"

      result = Parser.parse(markup)
      expected = [{"div", [], []}]

      assert result == expected
    end
  end
end
