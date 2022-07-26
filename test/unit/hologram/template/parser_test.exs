defmodule Hologram.Template.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.{Parser, SyntaxError}
  
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

  test "handles escaped JS code" do
    js_code = """
    function isPositiveNumber(param) \\{
      if (param > 0) \\{
        return true;
      \\}
      if (param <= 0) \\{
        return false;
      \\}
    \\}
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
