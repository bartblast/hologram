defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.{Parser, SyntaxError}

  defp assert_syntax_error(markup, message) do
    message = "\n#{message}" |> String.replace_trailing("\n", "")

    assert_raise SyntaxError, message, fn ->
      Parser.parse!(markup)
    end
  end

  defp attr_val_expr(value) do
    "~Hologram.Template.AttributeValueExpression[#{value}]"
  end

  test "text node" do
    markup = "abc"

    result = Parser.parse!(markup)
    expected = ["abc"]

    assert result == expected
  end

  test "single element node" do
    markup = "<div></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [], []}]

    assert result == expected
  end

  test "multiple non-nested element nodes" do
    markup = "<div></div><span></span>"

    result = Parser.parse!(markup)
    expected = [{"div", [], []}, {"span", [], []}]

    assert result == expected
  end

  test "multiple nested element nodes" do
    markup = "<div><span></span></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [], [{"span", [], []}]}]

    assert result == expected
  end

  test "multiple nested element and text nodes" do
    markup = "<div><span>abc</span></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [], [{"span", [], ["abc"]}]}]

    assert result == expected
  end

  test "single attribute with literal value" do
    markup = "<div class=\"abc\"></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", "abc"}], []}]

    assert result == expected
  end

  test "multiple attributes with literal value" do
    markup = "<div class=\"abc\" id=\"xyz\"></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", "abc"}, {"id", "xyz"}], []}]

    assert result == expected
  end

  test "single attribute with expression value" do
    markup = "<div class={abc}></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", attr_val_expr("abc")}], []}]

    assert result == expected
  end

  test "multiple attributes with expression value" do
    markup = "<div class={abc} id={xyz}></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", attr_val_expr("abc")}, {"id", attr_val_expr("xyz")}], []}]

    assert result == expected
  end

  test "attribute with literal value followed by attribute with expression value" do
    markup = "<div class=\"abc\" id={xyz}></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", "abc"}, {"id", attr_val_expr("xyz")}], []}]

    assert result == expected
  end

  test "attribute with expression value followed by attribute with literal value" do
    markup = "<div class={abc} id=\"xyz\"></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", attr_val_expr("abc")}, {"id", "xyz"}], []}]

    assert result == expected
  end

  test "special characters in attribute with literal value" do
    attr_value = "abc \n \r \t </ /> < > / = { }"
    markup = "<div class=\"#{attr_value}\"></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", attr_value}], []}]

    assert result == expected
  end

  test "special characters in attribute with expression value" do
    attr_value = "abc \n \r \t </ /> < > / = \" { }"
    markup = "<div class={#{attr_value}}></div>"

    result = Parser.parse!(markup)
    expected = [{"div", [{"class", attr_val_expr(attr_value)}], []}]

    assert result == expected
  end

  test "special characters in text node" do
    markup = "abc \n \r \t < > / = \" { }"

    result = Parser.parse!(markup)
    expected = [markup]

    assert result == expected
  end

  test "syntax error message" do
    markup = "<div class=\"test\" abcdefghij= 1234567890123456789012345"

    message = """
    s="test" abcdefghij= 12345678901234567890
                        ^
    """

    assert_syntax_error(markup, message)
  end

  test "removes doctype" do
    markup = "<!DoCtYpE html test_1 test_2>content"

    result = Parser.parse!(markup)
    expected = ["content"]

    assert result == expected
  end

  test "trims leading and trailing whitespaces" do
    markup = "\n\t content \t\n"

    result = Parser.parse!(markup)
    expected = ["content"]

    assert result == expected
  end
end
