defmodule Hologram.Template.ParserTest do
  use Hologram.TestCase, async: true
  alias Hologram.Template.Parser

  test "single node" do
    html = "<div></div>"

    result = Parser.parse(html)
    expected = {:ok, [{"div", [], []}]}

    assert result == expected
  end

  test "multiple nodes" do
    html = "<div></div><span></span>"

    result = Parser.parse(html)
    expected = {:ok, [{"div", [], []}, {"span", [], []}]}

    assert result == expected
  end

  test "attrs" do
    html = "<div class=\"value_class\" id=\"value_id\"></div>"

    result = Parser.parse(html)
    expected = {:ok, [{"div", [{"class", "value_class"}, {"id", "value_id"}], []}]}

    assert result == expected
  end

  test "children" do
    html = "<div><span></span><h1></h1></div>"

    result = Parser.parse(html)
    expected = {:ok, [{"div", [], [{"span", [], []}, {"h1", [], []}]}]}

    assert result == expected
  end

  test "interpolation quotes fixing" do
    html = """
    <div class=\"test_class_1\" abc={{ @abc }} id=\"test_id_1\" bcd={{ @bcd }}>
      <span class=\"test_class_2\" cde={{ @cde }} id=\"test_id_2\" def={{ @def }}></span>
    </div>
    """

    result = Parser.parse(html)

    expected =
      {:ok,
       [
         {"div",
          [
            {"class", "test_class_1"},
            {"abc", "{{ @abc }}"},
            {"id", "test_id_1"},
            {"bcd", "{{ @bcd }}"}
          ],
          [
            "\n  ",
            {"span",
             [
               {"class", "test_class_2"},
               {"cde", "{{ @cde }}"},
               {"id", "test_id_2"},
               {"def", "{{ @def }}"}
             ], []},
            "\n"
          ]},
         "\n"
       ]}

    assert result == expected
  end

  test "invalid html" do
    html = "<div"
    result = Parser.parse(html)

    expected =
      {:error,
       %Saxy.ParseError{
         binary: "<root><div</root>",
         position: 10,
         reason: {:token, :name_start_char}
       }}

    assert result == expected
  end
end
