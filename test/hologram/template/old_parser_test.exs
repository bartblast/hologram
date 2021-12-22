ga defmodule Hologram.Template.OldParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.OldParser

  test "single node" do
    markup = "<div></div>"

    result = OldParser.parse(markup)
    expected = {:ok, [{"div", [], []}]}

    assert result == expected
  end

  test "multiple nodes" do
    markup = "<div></div><span></span>"

    result = OldParser.parse(markup)
    expected = {:ok, [{"div", [], []}, {"span", [], []}]}

    assert result == expected
  end

  test "attrs" do
    markup = "<div class=\"value_class\" id=\"value_id\"></div>"

    result = OldParser.parse(markup)
    expected = {:ok, [{"div", [{"class", "value_class"}, {"id", "value_id"}], []}]}

    assert result == expected
  end

  test "children" do
    markup = "<div><span></span><h1></h1></div>"

    result = OldParser.parse(markup)
    expected = {:ok, [{"div", [], [{"span", [], []}, {"h1", [], []}]}]}

    assert result == expected
  end

  test "interpolation quotes fixing" do
    markup = """
    <div class=\"test_class_1\" abc={@abc} id=\"test_id_1\" bcd={@bcd}>
      <span class=\"test_class_2\" cde={@cde} id=\"test_id_2\" def={@def}></span>
    </div>
    """

    result = OldParser.parse(markup)

    expected =
      {:ok,
       [
         {"div",
          [
            {"class", "test_class_1"},
            {"abc", "{@abc}"},
            {"id", "test_id_1"},
            {"bcd", "{@bcd}"}
          ],
          [
            "\n  ",
            {"span",
             [
               {"class", "test_class_2"},
               {"cde", "{@cde}"},
               {"id", "test_id_2"},
               {"def", "{@def}"}
             ], []},
            "\n"
          ]}
       ]}

    assert result == expected
  end

  test "invalid html" do
    markup = "<div"
    result = OldParser.parse(markup)

    expected =
      {:error,
       %Saxy.ParseError{
         binary: "<root><div</root>",
         position: 10,
         reason: {:token, :name_start_char}
       }}

    assert result == expected
  end

  test "removes doctype and trims leading and trailing white chars" do
    markup = """
    \n\t <!DoCtYpE html test_1 test_2> \t\n
    content \t\n
    """

    result = OldParser.parse(markup)
    assert result == {:ok, ["content"]}
  end
end
