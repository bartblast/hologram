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

    test "ended by start tag" do
      markup = "abc<div>"

      result = assemble(markup)
      expected = [text: "abc", start_tag: {"div", []}]

      assert result == expected
    end

    test "ended by end tag" do
      markup = "abc</div>"

      result = assemble(markup)
      expected = [text: "abc", end_tag: "div"]

      assert result == expected
    end

    test "ended by block start" do
      markup = "abc{#xyz}"

      result = assemble(markup)
      expected = [text: "abc", block_start: {"xyz", "{}"}]

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

    test "inside text" do
      markup = "abc<div>xyz"

      result = assemble(markup)
      expected = [text: "abc", start_tag: {"div", []}, text: "xyz"]

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

    test "inside text" do
      markup = "abc</div>xyz"

      result = assemble(markup)
      expected = [text: "abc", end_tag: "div", text: "xyz"]

      assert result == expected
    end
  end

  describe "element" do
    test "single" do
      markup = "<div></div>"

      result = assemble(markup)
      expected = [start_tag: {"div", []}, end_tag: "div"]

      assert result == expected
    end

    test "multiple, siblings" do
      markup = "<span></span><button></button>"
      result = assemble(markup)

      expected = [
        start_tag: {"span", []},
        end_tag: "span",
        start_tag: {"button", []},
        end_tag: "button"
      ]

      assert result == expected
    end

    test "multiple, nested" do
      markup = "<div><span></span></div>"
      result = assemble(markup)

      expected = [
        start_tag: {"div", []},
        start_tag: {"span", []},
        end_tag: "span",
        end_tag: "div"
      ]

      assert result == expected
    end
  end

  describe "component" do
    test "single" do
      markup = "<Abc.Bcd></Abc.Bcd>"

      result = assemble(markup)
      expected = [start_tag: {"Abc.Bcd", []}, end_tag: "Abc.Bcd"]

      assert result == expected
    end

    test "multiple, siblings" do
      markup = "<Abc.Bcd></Abc.Bcd><Efg.Fgh></Efg.Fgh>"
      result = assemble(markup)

      expected = [
        start_tag: {"Abc.Bcd", []},
        end_tag: "Abc.Bcd",
        start_tag: {"Efg.Fgh", []},
        end_tag: "Efg.Fgh"
      ]

      assert result == expected
    end

    test "multiple, nested" do
      markup = "<Abc.Bcd><Efg.Fgh></Efg.Fgh></Abc.Bcd>"
      result = assemble(markup)

      expected = [
        start_tag: {"Abc.Bcd", []},
        start_tag: {"Efg.Fgh", []},
        end_tag: "Efg.Fgh",
        end_tag: "Abc.Bcd"
      ]

      assert result == expected
    end
  end

  describe "attribute" do
    test "text" do
      markup = "<div id=\"test\">"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [text: "test"]}]}]

      assert result == expected
    end

    test "expression" do
      markup = "<div id={1 + 2}>"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [expression: "{1 + 2}"]}]}]

      assert result == expected
    end

    test "expression in double quotes" do
      markup = "<div id=\"{1 + 2}\">"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [text: "", expression: "{1 + 2}", text: ""]}]}]

      assert result == expected
    end

    test "text, expression" do
      markup = "<div id=\"abc{1 + 2}\">"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [text: "abc", expression: "{1 + 2}", text: ""]}]}]

      assert result == expected
    end

    test "expression, text" do
      markup = "<div id=\"{1 + 2}abc\">"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [text: "", expression: "{1 + 2}", text: "abc"]}]}]

      assert result == expected
    end

    test "text, expression, text" do
      markup = "<div id=\"abc{1 + 2}xyz\">"

      result = assemble(markup)
      expected = [start_tag: {"div", [{"id", [text: "abc", expression: "{1 + 2}", text: "xyz"]}]}]

      assert result == expected
    end

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

    test "multiple attributes" do
      markup = "<div attr_1=\"value_1\" attr_2=\"value_2\">"

      result = assemble(markup)

      expected = [
        start_tag: {"div", [{"attr_1", [text: "value_1"]}, {"attr_2", [text: "value_2"]}]}
      ]

      assert result == expected
    end
  end

  describe "expression" do
    test "empty" do
      markup = "{}"

      result = assemble(markup)
      expected = [expression: "{}"]

      assert result == expected
    end

    test "whitespaces" do
      markup = "{ \n\r\t}"

      result = assemble(markup)
      expected = [expression: "{ \n\r\t}"]

      assert result == expected
    end

    test "string, ASCI alphabet lowercase" do
      markup = "{abcdefghijklmnopqrstuvwxyz}"

      result = assemble(markup)
      expected = [expression: "{abcdefghijklmnopqrstuvwxyz}"]

      assert result == expected
    end

    test "string, ASCI alphabet uppercase" do
      markup = "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"

      result = assemble(markup)
      expected = [expression: "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"]

      assert result == expected
    end

    test "string, UTF-8 chars" do
      markup = "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}"

      result = assemble(markup)
      expected = [expression: "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}"]

      assert result == expected
    end

    test "symbols" do
      markup = "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}"

      result = assemble(markup)
      expected = [expression: "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}"]

      assert result == expected
    end

    test "single group of curly brackets" do
      markup = "{{123}}"

      result = assemble(markup)
      expected = [expression: "{{123}}"]

      assert result == expected
    end

    test "multiple groups of curly brackets" do
      markup = "{{1},{2}}"

      result = assemble(markup)
      expected = [expression: "{{1},{2}}"]

      assert result == expected
    end

    test "opening curly bracket escaping" do
      markup = "{{\"\\{123\"}}"

      result = assemble(markup)
      expected = [expression: "{{\"\\{123\"}}"]

      assert result == expected
    end

    test "closing curly bracket escaping" do
      markup = "{{\"123\\}\"}}"

      result = assemble(markup)
      expected = [expression: "{{\"123\\}\"}}"]

      assert result == expected
    end

    test "single group of double quotes" do
      markup = "{{\"123\"}}"

      result = assemble(markup)
      expected = [expression: "{{\"123\"}}"]

      assert result == expected
    end

    test "multiple groups of double quotes" do
      markup = "{{\"1\",\"2\"}}"

      result = assemble(markup)
      expected = [expression: "{{\"1\",\"2\"}}"]

      assert result == expected
    end

    test "double quote escaping" do
      markup = "{{1\\\"2}}"

      result = assemble(markup)
      expected = [expression: "{{1\\\"2}}"]

      assert result == expected
    end

    test "opening curly bracket inside double quoted string" do
      markup = "{{\"1\\{2\"}}"

      result = assemble(markup)
      expected = [expression: "{{\"1\\{2\"}}"]

      assert result == expected
    end

    test "closing curly bracket inside double quoted string" do
      markup = "{{\"1\\}2\"}}"

      result = assemble(markup)
      expected = [expression: "{{\"1\\}2\"}}"]

      assert result == expected
    end

    test "inside text" do
      markup = "abc{@kmn}xyz"

      result = assemble(markup)
      expected = [text: "abc", expression: "{@kmn}", text: "xyz"]

      assert result == expected
    end

    test "inside element" do
      markup = "<div>{@abc}</div>"

      result = assemble(markup)
      expected = [start_tag: {"div", []}, expression: "{@abc}", end_tag: "div"]

      assert result == expected
    end
  end

  describe "raw block" do
    test "block start" do
      markup = "{#raw}"

      result = assemble(markup)
      expected = []

      assert result == expected
    end

    test "block end" do
      markup = "{#raw}{/raw}"

      result = assemble(markup)
      expected = []

      assert result == expected
    end

    test "expression" do
      markup = "{#raw}{1 + 2}{/raw}"

      result = assemble(markup)
      expected = [text: "{1 + 2}"]

      assert result == expected
    end

    test "inside text" do
      markup = "abc{#raw}{/raw}xyz"

      result = assemble(markup)
      expected = [text: "abcxyz"]

      assert result == expected
    end

    test "nested template block" do
      markup = "{#raw}{#abc}{/abc}{/raw}"

      result = assemble(markup)
      expected = [text: "{#abc}{/abc}"]

      assert result == expected
    end
  end

  describe "block start" do
    test "without expression" do
      markup = "{#abc}"

      result = assemble(markup)
      expected = [block_start: {"abc", "{}"}]

      assert result == expected
    end

    test "with whitespace expression" do
      markup = "{#abc \n\r\t}"

      result = assemble(markup)
      expected = [block_start: {"abc", "{ \n\r\t}"}]

      assert result == expected
    end

    test "with non-whitespace expression" do
      markup = "{#if abc == {1, 2}}"

      result = assemble(markup)
      expected = [block_start: {"if", "{ abc == {1, 2}}"}]

      assert result == expected
    end

    test "inside text" do
      markup = "abc{#kmn}xyz"

      result = assemble(markup)
      expected = [text: "abc", block_start: {"kmn", "{}"}, text: "xyz"]

      assert result == expected
    end

    test "inside element" do
      markup = "<div>{#abc}</div>"

      result = assemble(markup)
      expected = [start_tag: {"div", []}, block_start: {"abc", "{}"}, end_tag: "div"]

      assert result == expected
    end
  end

  describe "block end" do
    test "isolated" do
      markup = "{/abc}"

      result = assemble(markup)
      expected = [block_end: "abc"]

      assert result == expected
    end

    test "inside text" do
      markup = "abc{/kmn}xyz"

      result = assemble(markup)
      expected = [text: "abc", block_end: "kmn", text: "xyz"]

      assert result == expected
    end
  end

  describe "block" do
    test "single" do
      markup = "{#abc}{/abc}"

      result = assemble(markup)
      expected = [block_start: {"abc", "{}"}, block_end: "abc"]

      assert result == expected
    end

    test "multiple, siblings" do
      markup = "{#abc}{/abc}{#xyz}{/xyz}"
      result = assemble(markup)

      expected = [
        block_start: {"abc", "{}"},
        block_end: "abc",
        block_start: {"xyz", "{}"},
        block_end: "xyz"
      ]

      assert result == expected
    end

    test "multiple, nested" do
      markup = "{#abc}{#xyz}{/xyz}{/abc}"
      result = assemble(markup)

      expected = [
        block_start: {"abc", "{}"},
        block_start: {"xyz", "{}"},
        block_end: "xyz",
        block_end: "abc"
      ]

      assert result == expected
    end
  end

  describe "script" do
    test "symbol '<' not inside double quoted string" do
      markup = "<script>1 < 2</script>"

      result = assemble(markup)
      expected = [start_tag: {"script", []}, text: "1 < 2", end_tag: "script"]

      assert result == expected
    end

    test "symbol '<' inside double quoted string" do
      markup = "<script>\"1 < 2\"</script>"

      result = assemble(markup)
      expected = [start_tag: {"script", []}, text: "\"1 < 2\"", end_tag: "script"]

      assert result == expected
    end

    test "symbol '>' not inside double quoted string" do
      markup = "<script>1 > 2</script>"

      result = assemble(markup)
      expected = [start_tag: {"script", []}, text: "1 > 2", end_tag: "script"]

      assert result == expected
    end

    test "symbol '>' inside double quoted string" do
      markup = "<script>\"1 > 2\"</script>"

      result = assemble(markup)
      expected = [start_tag: {"script", []}, text: "\"1 > 2\"", end_tag: "script"]

      assert result == expected
    end

    test "symbol '</' inside double quoted string" do
      markup = "<script>\"abc</xyz\"</script>"

      result = assemble(markup)
      expected = [start_tag: {"script", []}, text: "\"abc</xyz\"", end_tag: "script"]

      assert result == expected
    end
  end

  # TODO: cleanup

  # alias Hologram.Template.SyntaxError

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
  #   #     start_tag: {"div", [{"id", [text: "bbb{@test}ccc"]}]},
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
  #   #     start_tag: {"Abc.Bcd", [{"xyz", [text: "bbb{@test}ccc"]}]},
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

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_curly_brackets: 0, processed_tags: [], processed_tokens: [string: \"abc\", whitespace: \" \"], raw?: false, tag_name: nil, token_buffer: [string: \"abc\", whitespace: \" \"]}
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

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_curly_brackets: 0, processed_tags: [], processed_tokens: [string: \"abc\", whitespace: \" \"], raw?: false, tag_name: nil, token_buffer: [string: \"abc\", whitespace: \" \"]}
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

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :text_node, num_open_curly_brackets: 0, processed_tags: [], processed_tokens: [string: \"012345678901234567890123456789\", whitespace: \" \"], raw?: false, tag_name: nil, token_buffer: [string: \"012345678901234567890123456789\", whitespace: \" \"]}
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

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :element_node, num_open_curly_brackets: 0, processed_tags: [], processed_tokens: [symbol: :<, string: \"div\", whitespace: \" \"], raw?: false, tag_name: \"div\", token_buffer: []}
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

  #     context = %{attr_key: nil, attr_value: [], attrs: [], double_quote_open?: false, node_type: :element_node, num_open_curly_brackets: 0, processed_tags: [], processed_tokens: [symbol: :<, string: \"div\", whitespace: \" \"], raw?: false, tag_name: \"div\", token_buffer: []}
  #     """

  #     assert_raise SyntaxError, expected_msg, fn ->
  #       assemble(markup)
  #     end
  #   end
  # end
end
