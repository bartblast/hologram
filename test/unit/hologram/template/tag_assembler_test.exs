defmodule Hologram.Template.TagAssemblerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.TagAssembler
  alias Hologram.Template.Tokenizer

  def assemble(markup) do
    markup
    |> Tokenizer.tokenize()
    |> TagAssembler.assemble()
  end

  describe "text" do
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
      markup = "abc\\{xyz"

      result = assemble(markup)
      expected = [text: "abc{xyz"]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "abc\\}xyz"

      result = assemble(markup)
      expected = [text: "abc}xyz"]

      assert result == expected
    end

    test "text ended by start tag" do
      markup = "abc<div>"

      result = assemble(markup)
      expected = [text: "abc", start_tag: {"div", []}]

      assert result == expected
    end

    test "text ended by end tag" do
      markup = "abc</div>"

      result = assemble(markup)
      expected = [text: "abc", end_tag: "div"]

      assert result == expected
    end
  end

  describe "start tag" do
    test "non-void HTML element" do
      markup = "<div>"

      result = assemble(markup)
      expected = [start_tag: {"div", []}]

      assert result == expected
    end

    test "non-void SVG element" do
      markup = "<g>"

      result = assemble(markup)
      expected = [start_tag: {"g", []}]

      assert result == expected
    end

    test "void HTML element, unclosed" do
      markup = "<br>"

      result = assemble(markup)
      expected = [self_closing_tag: {"br", []}]

      assert result == expected
    end

    test "void HTML element, self-closed" do
      markup = "<br />"

      result = assemble(markup)
      expected = [self_closing_tag: {"br", []}]

      assert result == expected
    end

    test "void SVG element, unclosed" do
      markup = "<path>"

      result = assemble(markup)
      expected = [self_closing_tag: {"path", []}]

      assert result == expected
    end

    test "void SVG element, self-closed" do
      markup = "<path />"

      result = assemble(markup)
      expected = [self_closing_tag: {"path", []}]

      assert result == expected
    end

    test "slot element, unclosed" do
      markup = "<slot>"

      result = assemble(markup)
      expected = [self_closing_tag: {"slot", []}]

      assert result == expected
    end

    test "slot element, self-closed" do
      markup = "<slot />"

      result = assemble(markup)
      expected = [self_closing_tag: {"slot", []}]

      assert result == expected
    end

    test "component, unclosed" do
      markup = "<Abc.Bcd>"

      result = assemble(markup)
      expected = [start_tag: {"Abc.Bcd", []}]

      assert result == expected
    end

    test "component, self-closed" do
      markup = "<Abc.Bcd />"

      result = assemble(markup)
      expected = [self_closing_tag: {"Abc.Bcd", []}]

      assert result == expected
    end

    test "whitespace after tag name" do
      markup = "<div \n\r\t>"

      result = assemble(markup)
      expected = [start_tag: {"div", []}]

      assert result == expected
    end
  end

  describe "end tag" do
    test "element" do
      markup = "</div>"

      result = assemble(markup)
      expected = [end_tag: "div"]

      assert result == expected
    end

    test "component" do
      markup = "</Abc.Bcd>"

      result = assemble(markup)
      expected = [end_tag: "Abc.Bcd"]

      assert result == expected
    end

    test "whitespace after tag name" do
      markup = "</div \n\r\t>"

      result = assemble(markup)
      expected = [end_tag: "div"]

      assert result == expected
    end
  end

  describe "block start" do
    test "without expression" do
      markup = "{#raw}"

      result = assemble(markup)
      expected = [block_start: {"raw", ""}]

      assert result == expected
    end

    test "with whitespace expression" do
      markup = "{#raw \n\r\t}"

      result = assemble(markup)
      expected = [block_start: {"raw", ""}]

      assert result == expected
    end

    test "with non-whitespace expression" do
      markup = "{#if abc == {1, 2}}"

      result = assemble(markup)
      expected = [block_start: {"if", "abc == {1, 2}"}]

      assert result == expected
    end

    test "inside text" do
      markup = "abc{#raw}xyz"

      result = assemble(markup)
      expected = [text: "abc", block_start: {"raw", ""}, text: "xyz"]

      assert result == expected
    end
  end

  describe "expression in text node" do
    test "empty" do
      markup = "abc{}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "", text: "xyz"]

      assert result == expected
    end

    test "whitespaces" do
      markup = "abc{ \n\r\t}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: " \n\r\t", text: "xyz"]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abc{abcdefghijklmnopqrstuvwxyz}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "abcdefghijklmnopqrstuvwxyz", text: "xyz"]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "abc{ABCDEFGHIJKLMNOPQRSTUVWXYZ}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", text: "xyz"]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "abc{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", text: "xyz"]

      assert result == expected
    end

    test "symbols" do
      markup = "abc{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "!@#$%^&*()-_=+[];:'\\\"\\|,./?`~", text: "xyz"]

      assert result == expected
    end

    test "single group of curly brackets" do
      markup = "abc{{123}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{123}", text: "xyz"]

      assert result == expected
    end

    test "multiple groups of curly brackets" do
      markup = "abc{{{1},{2}}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{{1},{2}}", text: "xyz"]

      assert result == expected
    end

    test "single group of double quotes" do
      markup = "abc{\"123\"}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "\"123\"", text: "xyz"]

      assert result == expected
    end

    test "multiple groups of double quotes" do
      markup = "abc{[\"1\",\"2\"]}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "[\"1\",\"2\"]", text: "xyz"]

      assert result == expected
    end

    test "opening curly bracket inside double quoted string" do
      markup = "abc{{\"1{2\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{\"1{2\"}", text: "xyz"]

      assert result == expected
    end

    test "closing curly bracket inside double quoted string" do
      markup = "abc{{\"1}2\"}}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{\"1}2\"}", text: "xyz"]

      assert result == expected
    end

    test "double quote escaping" do
      markup = "abc{\"1\\\"2\"}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "\"1\\\"2\"", text: "xyz"]

      assert result == expected
    end

  #   test "expression in text node nested in element node" do
  #     markup = "<script>{@abc}</script>"

  #     result = assemble(markup)
  #     expected = [start_tag: {"script", []}, expression: "{@abc}", end_tag: "script"]

  #     assert result == expected
  #   end
  end

  # alias Hologram.Template.SyntaxError

  # describe "expression in attribute value" do
  #   test "empty" do
  #     markup = "<div id=\"abc{}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "whitespaces" do
  #     markup = "<div id=\"abc{ \n\r\t}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{ \n\r\t}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "string, ASCI alphabet lowercase" do
  #     markup = "<div id=\"abc{abcdefghijklmnopqrstuvwxyz}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div",
  #          [
  #            {"id",
  #             [
  #               literal: "abc",
  #               expression: "{abcdefghijklmnopqrstuvwxyz}",
  #               literal: "xyz"
  #             ]}
  #          ]}
  #     ]

  #     assert result == expected
  #   end

  #   test "string, ASCI alphabet uppercase" do
  #     markup = "<div id=\"abc{ABCDEFGHIJKLMNOPQRSTUVWXYZ}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div",
  #          [
  #            {"id",
  #             [
  #               literal: "abc",
  #               expression: "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}",
  #               literal: "xyz"
  #             ]}
  #          ]}
  #     ]

  #     assert result == expected
  #   end

  #   test "string, UTF-8 chars" do
  #     markup = "<div id=\"abc{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div",
  #          [
  #            {"id",
  #             [
  #               literal: "abc",
  #               expression: "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}",
  #               literal: "xyz"
  #             ]}
  #          ]}
  #     ]

  #     assert result == expected
  #   end

  #   test "symbols" do
  #     markup = "<div id=\"abc{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div",
  #          [
  #            {"id",
  #             [
  #               literal: "abc",
  #               expression: "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}",
  #               literal: "xyz"
  #             ]}
  #          ]}
  #     ]

  #     assert result == expected
  #   end

  #   test "single group of curly brackets" do
  #     markup = "<div id=\"abc{{123}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{{123}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "multiple groups of curly brackets" do
  #     markup = "<div id=\"abc{{1},{2}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{{1},{2}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "opening curly bracket escaping" do
  #     markup = "<div id=\"abc{{\"\\{123\"}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div", [{"id", [literal: "abc", expression: "{{\"\\{123\"}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "closing curly bracket escaping" do
  #     markup = "<div id=\"abc{{\"123\\}\"}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div", [{"id", [literal: "abc", expression: "{{\"123\\}\"}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "single group of double quotes" do
  #     markup = "<div id=\"abc{{\"123\"}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{{\"123\"}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "multiple groups of double quotes" do
  #     markup = "<div id=\"abc{{\"1\",\"2\"}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div", [{"id", [literal: "abc", expression: "{{\"1\",\"2\"}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "double quote escaping" do
  #     markup = "<div id=\"abc{{1\\\"2}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{{1\\\"2}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "opening curly bracket inside double quoted string" do
  #     markup = "<div id=\"abc{{\"1\\{2\"}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div", [{"id", [literal: "abc", expression: "{{\"1\\{2\"}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "closing curly bracket inside double quoted string" do
  #     markup = "<div id=\"abc{{\"1\\}2\"}}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag:
  #         {"div", [{"id", [literal: "abc", expression: "{{\"1\\}2\"}}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end
  # end

  # describe "attribute" do
  #   test "boolean attribute followed by whitespace" do
  #     markup = "<div my_attr >"

  #     result = assemble(markup)
  #     expected = [start_tag: {"div", [{"my_attr", []}]}]

  #     assert result == expected
  #   end

  #   test "boolean attribute followed by start tag closing" do
  #     markup = "<div my_attr>"

  #     result = assemble(markup)
  #     expected = [start_tag: {"div", [{"my_attr", []}]}]

  #     assert result == expected
  #   end

  #   test "literal attribute value" do
  #     markup = "<div id=\"test\">"

  #     result = assemble(markup)
  #     expected = [start_tag: {"div", [{"id", [literal: "test"]}]}]

  #     assert result == expected
  #   end

  #   test "expression attribute value" do
  #     markup = "<div id={@test}>"

  #     result = assemble(markup)
  #     expected = [start_tag: {"div", [{"id", [expression: "{@test}"]}]}]

  #     assert result == expected
  #   end

  #   test "double quoted expression attribute value (without string prefix or suffix)" do
  #     markup = "<div id=\"{@test}\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "", expression: "{@test}", literal: ""]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "double quoted expression attribute value with string prefix" do
  #     markup = "<div id=\"abc{@test}\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{@test}", literal: ""]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "double quoted expression attribute value with string suffix" do
  #     markup = "<div id=\"{@test}abc\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "", expression: "{@test}", literal: "abc"]}]}
  #     ]

  #     assert result == expected
  #   end

  #   test "double quoted expression attribute value with string prefix and suffix" do
  #     markup = "<div id=\"abc{@test}xyz\">"
  #     result = assemble(markup)

  #     expected = [
  #       start_tag: {"div", [{"id", [literal: "abc", expression: "{@test}", literal: "xyz"]}]}
  #     ]

  #     assert result == expected
  #   end
  # end

  # describe "text node nested in raw directive" do
  #   test "empty" do
  #     markup = "aaa{#raw}{/raw}bbb"

  #     result = assemble(markup)
  #     expected = [text: "aaabbb"]

  #     assert result == expected
  #   end

  #   test "text with expression" do
  #     markup = "aaa{#raw}bbb{@test}ccc{/raw}ddd"

  #     result = assemble(markup)
  #     expected = [text: "aaabbb{@test}cccddd"]

  #     assert result == expected
  #   end

  #   test "text with '=' char" do
  #     markup = "aaa{#raw}bbb = ccc{/raw}ddd"

  #     result = assemble(markup)
  #     expected = [text: "aaabbb = cccddd"]

  #     assert result == expected
  #   end

  #   test "text with '\"' char" do
  #     markup = "aaa{#raw}bbb \" ccc{/raw}ddd"

  #     result = assemble(markup)
  #     expected = [text: "aaabbb \" cccddd"]

  #     assert result == expected
  #   end

  #   # TODO: test
  #   # test "element node with double quoted expression attribute value" do
  #   #   markup = "aaa{#raw}<div id=\"bbb{@test}ccc\"></div>{/raw}ddd"
  #   #   result = assemble(markup)

  #   #   expected = [
  #   #     text: "aaa",
  #   #     start_tag: {"div", [{"id", [literal: "bbb{@test}ccc"]}]},
  #   #     end_tag: "div",
  #   #     text: "ddd"
  #   #   ]

  #   #   assert result == expected
  #   # end

  #   # test "element node with expression attribute value" do
  #   #   markup = "aaa{#raw}<div id={@test}></div>{/raw}"
  #   #   result = assemble(markup)

  #   #   expected = [
  #   #     text: "aaa",
  #   #     start_tag: {"div", [{"id", [expression: "{@test}"]}]},
  #   #     end_tag: "div"
  #   #   ]

  #   #   assert result == expected
  #   # end

  #   # test "component node with double quoted expression prop value" do
  #   #   markup = "aaa{#raw}<Abc.Bcd xyz=\"bbb{@test}ccc\"></Abc.Bcd>{/raw}ddd"
  #   #   result = assemble(markup)

  #   #   expected = [
  #   #     text: "aaa",
  #   #     start_tag: {"Abc.Bcd", [{"xyz", [literal: "bbb{@test}ccc"]}]},
  #   #     end_tag: "Abc.Bcd",
  #   #     text: "ddd"
  #   #   ]

  #   #   assert result == expected
  #   # end

  #   # test "component node with expression prop value" do
  #   #   markup = "aaa{#raw}<Abc.Bcd xyz={@test}></Abc.Bcd>{/raw}"
  #   #   result = assemble(markup)

  #   #   expected = [
  #   #     text: "aaa",
  #   #     start_tag: {"Abc.Bcd", [{"xyz", [expression: "{@test}"]}]},
  #   #     end_tag: "Abc.Bcd"
  #   #   ]

  #   #   assert result == expected
  #   # end

  #   # test "script with special symbols" do
  #   #   markup = """
  #   #   <script>
  #   #     {#raw}
  #   #       document.getElementById("test_elem").addEventListener("click", () => { history.forward() })
  #   #     {/raw}
  #   #   </script>
  #   #   """

  #   #   result = assemble(markup)
  #   # end
  # end

  # # TODO: cleanup
  # # test "JS script" do
  # #   markup = """
  # #   <script>
  # #   {#raw}
  # #   "absdfsd </dupa jaisa"
  # #     if (abc > 0 || xyz < 10) {
  # #       () => { test("param") }.()

  # #     }
  # #   {/raw}
  # #   </script>
  # #   """

  # #   result = assemble(markup)
  # #   IO.inspect(result)
  # #   # expected = [text: "aaabbb"]

  # #   # assert result == expected
  # # end

  # describe "template syntax errors" do
  #   test "unescaped '<' character inside text node" do
  #     markup = "abc < xyz"

  #     expected_msg = """


  #     Unescaped '<' character inside text node.
  #     To escape use HTML entity: '&lt;'

  #     abc < xyz
  #         ^

  #     status = :text

  #     token = {:symbol, :<}

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_braces: 0, processed_tags: [], processed_tokens: [string: \"abc\", whitespace: \" \"], raw?: false, tag_name: nil, token_buffer: [string: \"abc\", whitespace: \" \"]}
  #     """

  #     assert_raise SyntaxError, expected_msg, fn ->
  #       assemble(markup)
  #     end
  #   end

  #   test "unescaped '>' character inside text node" do
  #     markup = "abc > xyz"

  #     expected_msg = """


  #     Unescaped '>' character inside text node.
  #     To escape use HTML entity: '&gt;'

  #     abc > xyz
  #         ^

  #     status = :text

  #     token = {:symbol, :>}

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_braces: 0, processed_tags: [], processed_tokens: [string: \"abc\", whitespace: \" \"], raw?: false, tag_name: nil, token_buffer: [string: \"abc\", whitespace: \" \"]}
  #     """

  #     assert_raise SyntaxError, expected_msg, fn ->
  #       assemble(markup)
  #     end
  #   end

  #   test "previous fragment trimming in error message" do
  #     markup = "012345678901234567890123456789 > xyz"

  #     expected_msg = """


  #     Unescaped '>' character inside text node.
  #     To escape use HTML entity: '&gt;'

  #     1234567890123456789 > xyz
  #                         ^

  #     status = :text

  #     token = {:symbol, :>}

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_braces: 0, processed_tags: [], processed_tokens: [string: \"012345678901234567890123456789\", whitespace: \" \"], raw?: false, tag_name: nil, token_buffer: [string: \"012345678901234567890123456789\", whitespace: \" \"]}
  #     """

  #     assert_raise SyntaxError, expected_msg, fn ->
  #       assemble(markup)
  #     end
  #   end

  #   test "unclosed start tag" do
  #     markup = "<div "

  #     expected_msg = """


  #     Unclosed start tag.

  #     <div\s
  #          ^

  #     status = :start_tag

  #     token = nil

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :element_node, num_open_braces: 0, processed_tags: [], processed_tokens: [symbol: :<, string: \"div\", whitespace: \" \"], raw?: false, tag_name: \"div\", token_buffer: []}
  #     """

  #     assert_raise SyntaxError, expected_msg, fn ->
  #       assemble(markup)
  #     end
  #   end

  #   test "missing attribute name" do
  #     markup = "<div =\"abc\">"

  #     expected_msg = """


  #     Missing attribute name.

  #     <div ="abc">
  #          ^

  #     status = :start_tag

  #     token = {:symbol, :=}

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :element_node, num_open_braces: 0, processed_tags: [], processed_tokens: [symbol: :<, string: \"div\", whitespace: \" \"], raw?: false, tag_name: \"div\", token_buffer: []}
  #     """

  #     assert_raise SyntaxError, expected_msg, fn ->
  #       assemble(markup)
  #     end
  #   end
  # end
end
