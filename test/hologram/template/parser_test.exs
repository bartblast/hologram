defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.{Parser, SyntaxError}

  defp assert_syntax_error(markup, message) do
    message = "\n#{message}" |> String.replace_trailing("\n", "")

    assert_raise SyntaxError, message, fn ->
      Parser.parse!(markup)
    end
  end

  test "text node" do
    markup = "abc"

    result = Parser.parse!(markup)
    expected = [{:text, "abc"}]

    assert result == expected
  end

  test "regular element node" do
    markup = "<div></div>"

    result = Parser.parse!(markup)
    expected = [{:element, "div", [], []}]

    assert result == expected
  end

  test "regular component node" do
    markup = "<Abc.Bcd></Abc.Bcd>"

    result = Parser.parse!(markup)
    expected = [{:component, "Abc.Bcd", [], []}]

    assert result == expected
  end

  test "closed void element node" do
    markup = "<br />"

    result = Parser.parse!(markup)
    expected = [{:element, "br", [], []}]

    assert result == expected
  end

  test "closed void component node" do
    markup = "<Abc.Bcd />"

    result = Parser.parse!(markup)
    expected = [{:component, "Abc.Bcd", [], []}]

    assert result == expected
  end

  test "unclosed void element node" do
    markup = "<br>"

    result = Parser.parse!(markup)
    expected = [{:element, "br", [], []}]

    assert result == expected
  end

  test "unclosed non-void element node" do
    markup = "<div>"

    assert_raise SyntaxError, "div tag is unclosed", fn ->
      Parser.parse!(markup)
    end
  end

  test "unclosed component node" do
    markup = "<Abc.Bcd>"

    assert_raise SyntaxError, "Abc.Bcd tag is unclosed", fn ->
      Parser.parse!(markup)
    end
  end

  test "multiple nodes" do
    markup = "<div></div>abc<Abc.Bcd />"

    result = Parser.parse!(markup)
    expected = [{:element, "div", [], []}, {:text, "abc"}, {:component, "Abc.Bcd", [], []}]

    assert result == expected
  end

  test "nested nodes" do
    markup = "<div><span><Abc.Bcd>abc</Abc.Bcd></span></div>"
    result = Parser.parse!(markup)

    expected = [
      {:element, "div", [], [
        {:element, "span", [], [
          {:component, "Abc.Bcd", [], [
            {:text, "abc"}
          ]}
        ]}
      ]}
    ]

    assert result == expected
  end

  test "single attribute with literal value" do
    markup = "<div class=\"abc\"></div>"

    result = Parser.parse!(markup)
    expected = [{:element, "div", [{:literal, "class", "abc"}], []}]

    assert result == expected
  end

  test "multiple attributes with literal value" do
    markup = "<div class=\"abc\" id=\"xyz\"></div>"
    result = Parser.parse!(markup)

    expected = [{:element, "div", [
      {:literal, "class", "abc"},
      {:literal, "id", "xyz"}
    ], []}]

    assert result == expected
  end

  test "single attribute with expression value" do
    markup = "<div class={abc}></div>"

    result = Parser.parse!(markup)
    expected = [{:element, "div", [{:expression, "class", "abc"}], []}]

    assert result == expected
  end

  test "multiple attributes with expression value" do
    markup = "<div class={abc} id={xyz}></div>"
    result = Parser.parse!(markup)

    expected = [{:element, "div", [
      {:expression, "class", "abc"},
      {:expression, "id", "xyz"}
    ], []}]

    assert result == expected
  end

  test "attribute with literal value followed by attribute with expression value" do
    markup = "<div class=\"abc\" id={xyz}></div>"
    result = Parser.parse!(markup)

    expected = [{:element, "div", [
      {:literal, "class", "abc"},
      {:expression, "id", "xyz"}
    ], []}]

    assert result == expected
  end

  test "attribute with expression value followed by attribute with literal value" do
    markup = "<div class={abc} id=\"xyz\"></div>"
    result = Parser.parse!(markup)

    expected = [{:element, "div", [
      {:expression, "class", "abc"},
      {:literal, "id", "xyz"}
    ], []}]

    assert result == expected
  end

  test "special characters in attribute with literal value" do
    attr_value = "abc \n \r \t </ /> < > / = { }"
    markup = "<div class=\"#{attr_value}\"></div>"

    result = Parser.parse!(markup)
    expected = [{:element, "div", [{:literal, "class", attr_value}], []}]

    assert result == expected
  end

  test "special characters in attribute with expression value" do
    attr_value = "abc \n \r \t </ /> < > / = \" { }"
    markup = "<div class={#{attr_value}}></div>"

    result = Parser.parse!(markup)
    expected = [{:element, "div", [{:expression, "class", attr_value}], []}]

    assert result == expected
  end

  test "special characters in text node" do
    markup = "abc \n \r \t < > / = \" { }"

    result = Parser.parse!(markup)
    expected = [{:text, markup}]

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
    expected = [{:text, "content"}]

    assert result == expected
  end

  test "removes comments" do
    special_chars = "abc \n \r \t < > / = \" { } ! -"
    markup = "aaa<!-- #{special_chars} -->bbb<!-- #{special_chars} -->ccc"

    result = Parser.parse!(markup)
    expected = [{:text, "aaabbbccc"}]

    assert result == expected
  end

  test "handles JS code" do
    js_code = """
    function isPositiveNumber(param) {
      if (param > 0) {
        return true;
      }
      if (param <= 0) {
        return false;
      }
    }
    """

    markup = "<script>#{js_code}</script>"

    result = Parser.parse!(markup)
    expected = [{:element, "script", [], [{:text, js_code}]}]

    assert result == expected
  end

  test "trims leading and trailing whitespaces" do
    markup = "\n\t content \t\n"

    result = Parser.parse!(markup)
    expected = [{:text, "content"}]

    assert result == expected
  end
end
