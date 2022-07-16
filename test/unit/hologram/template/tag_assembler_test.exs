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
      expected = [text: markup]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abcdefghijklmnopqrstuvwxyz"

      result = assemble(markup)
      expected = [text: markup]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

      result = assemble(markup)
      expected = [text: markup]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"

      result = assemble(markup)
      expected = [text: markup]

      assert result == expected
    end

    test "symbols" do
      markup = "!@#$%^&*()-_=+[];:'\"\\|,./?`~"

      result = assemble(markup)
      expected = [text: markup]

      assert result == expected
    end

    test "opening curly bracket escaping" do
      markup = "\\{"

      result = assemble(markup)
      expected = [text: "{"]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "\\}"

      result = assemble(markup)
      expected = [text: "}"]

      assert result == expected
    end
  end

  describe "expression in text node" do
    test "empty" do
      markup = "abc{}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{}", text: "xyz"]

      assert result == expected
    end

    test "whitespaces" do
      markup = "abc{ \n\r\t}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{ \n\r\t}", text: "xyz"]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abc{abcdefghijklmnopqrstuvwxyz}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{abcdefghijklmnopqrstuvwxyz}", text: "xyz"]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "abc{ABCDEFGHIJKLMNOPQRSTUVWXYZ}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}", text: "xyz"]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "abc{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}", text: "xyz"]

      assert result == expected
    end

    test "symbols" do
      markup = "abc{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}", text: "xyz"]

      assert result == expected
    end

    test "single group of curly brackets" do
      markup = "abc{{123}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{123}}", text: "xyz"]

      assert result == expected
    end

    test "multiple groups of curly brackets" do
      markup = "abc{{1},{2}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{1},{2}}", text: "xyz"]

      assert result == expected
    end

    test "opening curly bracket escaping" do
      markup = "abc{{\"\\{123\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{\"\\{123\"}}", text: "xyz"]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "abc{{\"123\\}\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{\"123\\}\"}}", text: "xyz"]

      assert result == expected
    end

    test "single group of double quotes" do
      markup = "abc{{\"123\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{\"123\"}}", text: "xyz"]

      assert result == expected
    end

    test "multiple groups of double quotes" do
      markup = "abc{{\"1\",\"2\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{\"1\",\"2\"}}", text: "xyz"]

      assert result == expected
    end

    test "double quote escaping" do
      markup = "abc{{1\\\"2}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{1\\\"2}}", text: "xyz"]

      assert result == expected
    end

    test "opening curly bracket inside double quoted string" do
      markup = "abc{{\"1\\{2\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{\"1\\{2\"}}", text: "xyz"]

      assert result == expected
    end

    test "closing curly bracket inside double quoted string" do
      markup = "abc{{\"1\\}2\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{\"1\\}2\"}}", text: "xyz"]

      assert result == expected
    end
  end

  describe "expression in attribute value" do
    test "empty" do
      markup = "<div id=\"abc{}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "whitespaces" do
      markup = "<div id=\"abc{ \n\r\t}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{ \n\r\t}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "<div id=\"abc{abcdefghijklmnopqrstuvwxyz}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [
           {"id",
            [
              literal: "abc",
              expression: "{abcdefghijklmnopqrstuvwxyz}",
              literal: "xyz"
            ]}
         ]}
      ]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "<div id=\"abc{ABCDEFGHIJKLMNOPQRSTUVWXYZ}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [
           {"id",
            [
              literal: "abc",
              expression: "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}",
              literal: "xyz"
            ]}
         ]}
      ]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "<div id=\"abc{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [
           {"id",
            [
              literal: "abc",
              expression: "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}",
              literal: "xyz"
            ]}
         ]}
      ]

      assert result == expected
    end

    test "symbols" do
      markup = "<div id=\"abc{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [
           {"id",
            [
              literal: "abc",
              expression: "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}",
              literal: "xyz"
            ]}
         ]}
      ]

      assert result == expected
    end

    test "single group of curly brackets" do
      markup = "<div id=\"abc{{123}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{123}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "multiple groups of curly brackets" do
      markup = "<div id=\"abc{{1},{2}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{1},{2}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "opening curly bracket escaping" do
      markup = "<div id=\"abc{{\"\\{123\"}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{\"\\{123\"}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "<div id=\"abc{{\"123\\}\"}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{\"123\\}\"}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "single group of double quotes" do
      markup = "<div id=\"abc{{\"123\"}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{\"123\"}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "multiple groups of double quotes" do
      markup = "<div id=\"abc{{\"1\",\"2\"}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{\"1\",\"2\"}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "double quote escaping" do
      markup = "<div id=\"abc{{1\\\"2}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{1\\\"2}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "opening curly bracket inside double quoted string" do
      markup = "<div id=\"abc{{\"1\\{2\"}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{\"1\\{2\"}}", literal: "xyz"]}]}
      ]

      assert result == expected
    end

    test "closing curly bracket inside double quoted string" do
      markup = "<div id=\"abc{{\"1\\}2\"}}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{{\"1\\}2\"}}", literal: "xyz"]}]}
      ]

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

    test "start tag with whitespace after tag name" do
      markup = "<div \n\r\t>"

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

    test "end tag with whitespace after tag name" do
      markup = "</div \n\r\t>"

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

  describe "attribute" do
    test "boolean attribute followed by whitespace" do
      markup = "<div my_attr >"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"my_attr", []}]}]

      assert result == expected
    end

    test "boolean attribute followed by start tag closing" do
      markup = "<div my_attr>"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"my_attr", []}]}]

      assert result == expected
    end

    test "literal attribute value" do
      markup = "<div id=\"test\">"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [literal: "test"]}]}]

      assert result == expected
    end

    test "expression attribute value" do
      markup = "<div id={@test}>"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [expression: "@test"]}]}]

      assert result == expected
    end

    test "double quoted expression attribute value (without string prefix or suffix)" do
      markup = "<div id=\"{@test}\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div", [{"id", [literal: "", expression: "{@test}", literal: ""]}]}
      ]

      assert result == expected
    end

    test "double quoted expression attribute value with string prefix" do
      markup = "<div id=\"abc{@test}\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{@test}", literal: ""]}]}
      ]

      assert result == expected
    end

    test "double quoted expression attribute value with string suffix" do
      markup = "<div id=\"{@test}abc\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "", expression: "{@test}", literal: "abc"]}]}
      ]

      assert result == expected
    end

    test "double quoted expression attribute value with string prefix and suffix" do
      markup = "<div id=\"abc{@test}xyz\">"
      result = assemble(markup)

      expected = [
        start_tag: {"div",
         [{"id", [literal: "abc", expression: "{@test}", literal: "xyz"]}]}
      ]

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

      status = :text

      context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_braces: 0, processed_tags: [], processed_tokens: [string: \"abc\", whitespace: \" \"], tag_name: nil, token_buffer: [string: \"abc\", whitespace: \" \"]}
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

      status = :text

      context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_braces: 0, processed_tags: [], processed_tokens: [string: \"abc\", whitespace: \" \"], tag_name: nil, token_buffer: [string: \"abc\", whitespace: \" \"]}
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble(markup)
      end
    end

    test "previous fragment trimming in error message" do
      markup = "012345678901234567890123456789 > xyz"

      expected_msg = """


      Unescaped '>' character inside text node.
      To escape use HTML entity: '&gt;'

      1234567890123456789 > xyz
                          ^

      status = :text

      context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_braces: 0, processed_tags: [], processed_tokens: [string: \"012345678901234567890123456789\", whitespace: \" \"], tag_name: nil, token_buffer: [string: \"012345678901234567890123456789\", whitespace: \" \"]}
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble(markup)
      end
    end
  end
end
