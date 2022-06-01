defmodule Hologram.Template.TagAssemblerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.SyntaxError
  alias Hologram.Template.TagAssembler
  alias Hologram.Template.Tokenizer

  def assemble(markup) do
    markup
    |> Tokenizer.tokenize()
    |> TagAssembler.assemble()
  end

  describe "text node" do
    test "empty" do
      markup = ""

      result = assemble(markup)
      expected = []

      assert result == expected
    end

    test "whitespaces" do
      markup = " \n\r\t"

      result = assemble(markup)
      expected = [text_tag: markup]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abcdefghijklmnopqrstuvwxyz"

      result = assemble(markup)
      expected = [text_tag: markup]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

      result = assemble(markup)
      expected = [text_tag: markup]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"

      result = assemble(markup)
      expected = [text_tag: markup]

      assert result == expected
    end

    test "symbols" do
      markup = "!@#$%^&*()-_=+[];:'\"\\|,./?`~"

      result = assemble(markup)
      expected = [text_tag: markup]

      assert result == expected
    end

    test "opening curly bracket escaping" do
      markup = "\\{"

      result = assemble(markup)
      expected = [text_tag: "{"]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "\\}"

      result = assemble(markup)
      expected = [text_tag: "}"]

      assert result == expected
    end
  end

  describe "expression in text node" do
    test "empty" do
      markup = "abc{}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{}", text_tag: "xyz"]

      assert result == expected
    end

    test "whitespaces" do
      markup = "abc{ \n\r\t}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{ \n\r\t}", text_tag: "xyz"]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abc{abcdefghijklmnopqrstuvwxyz}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{abcdefghijklmnopqrstuvwxyz}", text_tag: "xyz"]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "abc{ABCDEFGHIJKLMNOPQRSTUVWXYZ}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}", text_tag: "xyz"]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "abc{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}", text_tag: "xyz"]

      assert result == expected
    end

    test "symbols" do
      markup = "abc{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}", text_tag: "xyz"]

      assert result == expected
    end

    test "single group of curly brackets" do
      markup = "abc{{123}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{123}}", text_tag: "xyz"]

      assert result == expected
    end

    test "multiple groups of curly brackets" do
      markup = "abc{{1},{2}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{1},{2}}", text_tag: "xyz"]

      assert result == expected
    end

    test "opening curly bracket escaping" do
      markup = "abc{{\"\\{123\"}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{\"\\{123\"}}", text_tag: "xyz"]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "abc{{\"123\\}\"}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{\"123\\}\"}}", text_tag: "xyz"]

      assert result == expected
    end

    test "single group of double quotes" do
      markup = "abc{{\"123\"}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{\"123\"}}", text_tag: "xyz"]

      assert result == expected
    end

    test "multiple groups of double quotes" do
      markup = "abc{{\"1\",\"2\"}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{\"1\",\"2\"}}", text_tag: "xyz"]

      assert result == expected
    end

    test "double quote escaping" do
      markup = "abc{{1\\\"2}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{1\\\"2}}", text_tag: "xyz"]

      assert result == expected
    end

    test "opening curly bracket inside double quoted string" do
      markup = "abc{{\"1\\{2\"}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{\"1\\{2\"}}", text_tag: "xyz"]

      assert result == expected
    end

    test "closing curly bracket inside double quoted string" do
      markup = "abc{{\"1\\}2\"}}xyz"

      result = assemble(markup)
      expected = [text_tag: "abc", expression: "{{\"1\\}2\"}}", text_tag: "xyz"]

      assert result == expected
    end
  end

  describe "element node" do
    test "start tag" do
      markup = "<div>"

      result = assemble(markup)
      expected = [start_tag: {"div", []}]

      assert result == expected
    end

    test "end tag" do
      markup = "</div>"

      result = assemble(markup)
      expected = [end_tag: "div"]

      assert result == expected
    end

    test "self-closed non-svg tag" do
      markup = "<br />"

      result = assemble(markup)
      expected = [self_closing_tag: {"br", []}]

      assert result == expected
    end

    test "self-closed svg tag" do
      markup = "<path />"

      result = assemble(markup)
      expected = [self_closing_tag: {"path", []}]

      assert result == expected
    end

    test "self-closed slot tag" do
      markup = "<slot />"

      result = assemble(markup)
      expected = [self_closing_tag: {"slot", []}]

      assert result == expected
    end

    test "non self-closed non-svg tag" do
      markup = "<br>"

      result = assemble(markup)
      expected = [self_closing_tag: {"br", []}]

      assert result == expected
    end

    test "not self-closed svg tag" do
      markup = "<path>"

      result = assemble(markup)
      expected = [self_closing_tag: {"path", []}]

      assert result == expected
    end

    test "not self-closed slot tag" do
      markup = "<slot>"

      result = assemble(markup)
      expected = [self_closing_tag: {"slot", []}]

      assert result == expected
    end
  end

  describe "component node" do
    test "start tag" do
      markup = "<Abc.Bcd>"

      result = assemble(markup)
      expected = [start_tag: {"Abc.Bcd", []}]

      assert result == expected
    end

    test "end tag" do
      markup = "</Abc.Bcd>"

      result = assemble(markup)
      expected = [end_tag: "Abc.Bcd"]

      assert result == expected
    end

    test "self-closed tag" do
      markup = "<Abc.Bcd />"

      result = assemble(markup)
      expected = [self_closing_tag: {"Abc.Bcd", []}]

      assert result == expected
    end
  end

  describe "template syntax errors" do
    test "unescaped '<' character inside text node" do
      markup = "abc < xyz"

      expected_msg = """


      Unescaped '<' character inside text node.
      To escape use HTML entity: '&lt;'

      abc < xyz
          ^
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble(markup)
      end
    end

    test "unescaped '>' character inside text node" do
      markup = "abc > xyz"

      expected_msg = """


      Unescaped '>' character inside text node.
      To escape use HTML entity: '&gt;'

      abc > xyz
          ^
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble(markup)
      end
    end
  end
end







































#   describe "attribute" do
#     test "literal value" do
#       markup = "<div id=\"test\">"

#       result = assemble(markup)
#       expected = [start_tag: {"div", [{:literal, "id", [string: "test"]}]}]

#       assert result == expected
#     end

#     test "expression value" do
#       markup = "<div id={@test}>"

#       result = assemble(markup)
#       expected = [start_tag: {"div", [{:expression, "id", [string: "@test"]}]}]

#       assert result == expected
#     end

#     test "literal value with interpolation without string prefix or suffix" do
#       markup = "<div id=\"{@test}\">"

#       result = assemble(markup)

#       expected = [
#         start_tag: {"div",
#          [{:literal, "id", [symbol: :"{", string: "@test", symbol: :"}"]}]}
#       ]

#       assert result == expected
#     end

#     test "literal value with interpolation with string prefix" do
#       markup = "<div id=\"abc{@test}\">"

#       result = assemble(markup)

#       expected = [
#         start_tag: {"div",
#          [
#            {:literal, "id",
#             [string: "abc", symbol: :"{", string: "@test", symbol: :"}"]}
#          ]}
#       ]

#       assert result == expected
#     end

#     test "literal value with interpolation with string suffix" do
#       markup = "<div id=\"{@test}abc\">"

#       result = assemble(markup)

#       expected = [
#         start_tag: {"div",
#          [
#            {:literal, "id",
#             [symbol: :"{", string: "@test", symbol: :"}", string: "abc"]}
#          ]}
#       ]

#       assert result == expected
#     end

#     test "literal value with interpolation with string prefix and suffix" do
#       markup = "<div id=\"abc{@test}xyz\">"

#       result = assemble(markup)

#       expected = [
#         start_tag: {"div",
#          [
#            {:literal, "id",
#             [
#               string: "abc",
#               symbol: :"{",
#               string: "@test",
#               symbol: :"}",
#               string: "xyz"
#             ]}
#          ]}
#       ]

#       assert result == expected
#     end
#   end
# end
