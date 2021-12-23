defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.{Parser, SyntaxError}

  defp assert_syntax_error(markup, message) do
    message = "\n#{message}" |> String.replace_trailing("\n", "")

    assert_raise SyntaxError, message, fn ->
      Parser.parse(markup)
    end
  end

  test "text node" do
    markup = "abc"

    result = Parser.parse(markup)
    expected = ["abc"]

    assert result == expected
  end

  test "single element node" do
    markup = "<div></div>"

    result = Parser.parse(markup)
    expected = [{"div", [], []}]

    assert result == expected
  end

  test "multiple non-nested element nodes" do
    markup = "<div></div><span></span>"

    result = Parser.parse(markup)
    expected = [{"div", [], []}, {"span", [], []}]

    assert result == expected
  end

  test "multiple nested element nodes" do
    markup = "<div><span></span></div>"

    result = Parser.parse(markup)
    expected = [{"div", [], [{"span", [], []}]}]

    assert result == expected
  end

  test "multiple nested element and text nodes" do
    markup = "<div><span>abc</span></div>"

    result = Parser.parse(markup)
    expected = [{"div", [], [{"span", [], ["abc"]}]}]

    assert result == expected
  end

  test "syntax error message" do
    markup = "1234567890123456789012345< 1234567890123456789012345"

    message = """
    7890123456789012345< 12345678901234567890
                        ^
    """

    assert_syntax_error(markup, message)
  end
end
