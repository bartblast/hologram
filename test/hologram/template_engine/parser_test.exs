defmodule Hologram.TemplateEngine.ParserTest do
  use ExUnit.Case
  alias Hologram.TemplateEngine.Parser

  describe "parse/1" do
    test "valid html" do
      assert {:ok, _} = Parser.parse("<div></div>")
    end

    # TODO: find invalid case
    # test "invalid html" do
    #   assert {:error, _} = Parser.parse("<div ")
    # end

    test "interpolation quotes fixing" do
      html = """
        <div class=\"test_class_1\" abc={{ @abc }} id=\"test_id_1\" bcd={{ @bcd }}>
          <span class=\"test_class_2\" cde={{ @cde }} id=\"test_id_2\" def={{ @def }}></span>
        </div>
      """

      result = Parser.parse(html)

      expected = {:ok,
      {"div",
       [
         {"class", "test_class_1"},
         {"abc", "{{ @abc }}"},
         {"id", "test_id_1"},
         {"bcd", "{{ @bcd }}"}
       ],
       [
         "\n    ",
         {"span",
          [
            {"class", "test_class_2"},
            {"cde", "{{ @cde }}"},
            {"id", "test_id_2"},
            {"def", "{{ @def }}"}
          ], []},
         "\n  "
       ]}}

      assert result == expected
    end
  end
end
