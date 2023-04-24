defmodule Hologram.Template.TagAssemblerTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Template.SyntaxError
  alias Hologram.Template.TagAssembler
  alias Hologram.Template.Tokenizer

  def assemble(markup) do
    markup
    |> Tokenizer.tokenize()
    |> TagAssembler.assemble()
  end

  describe "text" do
    test "empty" do
      assert assemble("") == []
    end

    test "whitespaces" do
      markup = " \n\r\t"
      assert assemble(markup) == [text: markup]
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abcdefghijklmnopqrstuvwxyz"
      assert assemble(markup) == [text: markup]
    end

    test "string, ASCI alphabet uppercase" do
      markup = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      assert assemble(markup) == [text: markup]
    end

    test "string, UTF-8 chars" do
      markup = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"
      assert assemble(markup) == [text: markup]
    end

    test "symbols" do
      markup = "!@#$%^&*()-_=+[];:'\"\\|,./?`~"
      assert assemble(markup) == [text: markup]
    end

    test "opening curly bracket escaping" do
      assert assemble("abc\\{xyz") == [text: "abc{xyz"]
    end

    test "closing curly bracket escaping" do
      assert assemble("abc\\}xyz") == [text: "abc}xyz"]
    end

    test "ended by element start tag" do
      assert assemble("abc<div>") == [text: "abc", start_tag: {"div", []}]
    end

    test "ended by component start tag" do
      assert assemble("abc<Aaa.Bbb>") == [text: "abc", start_tag: {"Aaa.Bbb", []}]
    end

    test "ended by element end tag" do
      assert assemble("abc</div>") == [text: "abc", end_tag: "div"]
    end

    test "ended by component end tag" do
      assert assemble("abc</Aaa.Bbb>") == [text: "abc", end_tag: "Aaa.Bbb"]
    end

    test "ended by block start" do
      assert assemble("abc{#xyz}") == [text: "abc", block_start: {"xyz", "{}"}]
    end
  end

  describe "start tag" do
    test "non-void HTML element" do
      assert assemble("<div>") == [start_tag: {"div", []}]
    end

    test "non-void SVG element" do
      assert assemble("<g>") == [start_tag: {"g", []}]
    end

    test "void HTML element, unclosed" do
      assert assemble("<br>") == [self_closing_tag: {"br", []}]
    end

    test "void HTML element, self-closed" do
      assert assemble("<br />") == [self_closing_tag: {"br", []}]
    end

    test "void SVG element, unclosed" do
      assert assemble("<path>") == [self_closing_tag: {"path", []}]
    end

    test "void SVG element, self-closed" do
      assert assemble("<path />") == [self_closing_tag: {"path", []}]
    end

    test "slot element, unclosed" do
      assert assemble("<slot>") == [self_closing_tag: {"slot", []}]
    end

    test "slot element, self-closed" do
      assert assemble("<slot />") == [self_closing_tag: {"slot", []}]
    end

    test "component, unclosed" do
      assert assemble("<Aaa.Bbb>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "component, self-closed" do
      assert assemble("<Aaa.Bbb />") == [self_closing_tag: {"Aaa.Bbb", []}]
    end

    test "whitespace after element tag name" do
      assert assemble("<div \n\r\t>") == [start_tag: {"div", []}]
    end

    test "whitespace after component tag name" do
      assert assemble("<Aaa.Bbb \n\r\t>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "inside text, element" do
      assert assemble("abc<div>xyz") == [text: "abc", start_tag: {"div", []}, text: "xyz"]
    end

    test "inside text, component" do
      assert assemble("abc<Aaa.Bbb>xyz") == [text: "abc", start_tag: {"Aaa.Bbb", []}, text: "xyz"]
    end
  end

  describe "end tag" do
    test "element" do
      assert assemble("</div>") == [end_tag: "div"]
    end

    test "component" do
      assert assemble("</Aaa.Bbb>") == [end_tag: "Aaa.Bbb"]
    end

    test "whitespace after element tag name" do
      assert assemble("</div \n\r\t>") == [end_tag: "div"]
    end

    test "whitespace after component tag name" do
      assert assemble("</Aaa.Bbb \n\r\t>") == [end_tag: "Aaa.Bbb"]
    end

    test "inside text, element" do
      assert assemble("abc</div>xyz") == [text: "abc", end_tag: "div", text: "xyz"]
    end

    test "inside text, component" do
      assert assemble("abc</Aaa.Bbb>xyz") == [text: "abc", end_tag: "Aaa.Bbb", text: "xyz"]
    end
  end

  describe "element" do
    test "single" do
      assert assemble("<div></div>") == [start_tag: {"div", []}, end_tag: "div"]
    end

    test "multiple, siblings" do
      assert assemble("<span></span><button></button>") == [
               start_tag: {"span", []},
               end_tag: "span",
               start_tag: {"button", []},
               end_tag: "button"
             ]
    end

    test "multiple, nested" do
      assert assemble("<div><span></span></div>") == [
               start_tag: {"div", []},
               start_tag: {"span", []},
               end_tag: "span",
               end_tag: "div"
             ]
    end
  end

  describe "component" do
    test "single" do
      assert assemble("<Aaa.Bbb></Aaa.Bbb>") == [start_tag: {"Aaa.Bbb", []}, end_tag: "Aaa.Bbb"]
    end

    test "multiple, siblings" do
      assert assemble("<Aaa.Bbb></Aaa.Bbb><Eee.Fff></Eee.Fff>") == [
               start_tag: {"Aaa.Bbb", []},
               end_tag: "Aaa.Bbb",
               start_tag: {"Eee.Fff", []},
               end_tag: "Eee.Fff"
             ]
    end

    test "multiple, nested" do
      assert assemble("<Aaa.Bbb><Eee.Fff></Eee.Fff></Aaa.Bbb>") == [
               start_tag: {"Aaa.Bbb", []},
               start_tag: {"Eee.Fff", []},
               end_tag: "Eee.Fff",
               end_tag: "Aaa.Bbb"
             ]
    end
  end

  describe "attribute" do
    test "text" do
      assert assemble("<div id=\"test\">") == [start_tag: {"div", [{"id", [text: "test"]}]}]
    end

    test "expression" do
      assert assemble("<div id={1 + 2}>") == [
               start_tag: {"div", [{"id", [expression: "{1 + 2}"]}]}
             ]
    end

    test "expression in double quotes" do
      assert assemble("<div id=\"{1 + 2}\">") == [
               start_tag: {"div", [{"id", [text: "", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "text, expression" do
      assert assemble("<div id=\"abc{1 + 2}\">") == [
               start_tag: {"div", [{"id", [text: "abc", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "expression, text" do
      assert assemble("<div id=\"{1 + 2}abc\">") == [
               start_tag: {"div", [{"id", [text: "", expression: "{1 + 2}", text: "abc"]}]}
             ]
    end

    test "text, expression, text" do
      assert assemble("<div id=\"abc{1 + 2}xyz\">") == [
               start_tag: {"div", [{"id", [text: "abc", expression: "{1 + 2}", text: "xyz"]}]}
             ]
    end

    test "boolean attribute followed by whitespace" do
      assert assemble("<div my_attr >") == [start_tag: {"div", [{"my_attr", []}]}]
    end

    test "boolean attribute followed by start tag closing" do
      assert assemble("<div my_attr>") == [start_tag: {"div", [{"my_attr", []}]}]
    end

    test "multiple attributes" do
      assert assemble("<div attr_1=\"value_1\" attr_2=\"value_2\">") == [
               start_tag: {"div", [{"attr_1", [text: "value_1"]}, {"attr_2", [text: "value_2"]}]}
             ]
    end
  end

  describe "property" do
    test "text" do
      assert assemble("<Aaa.Bbb id=\"test\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "test"]}]}
             ]
    end

    test "expression" do
      assert assemble("<Aaa.Bbb id={1 + 2}>") == [
               start_tag: {"Aaa.Bbb", [{"id", [expression: "{1 + 2}"]}]}
             ]
    end

    test "expression in double quotes" do
      assert assemble("<Aaa.Bbb id=\"{1 + 2}\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "text, expression" do
      assert assemble("<Aaa.Bbb id=\"abc{1 + 2}\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "abc", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "expression, text" do
      assert assemble("<Aaa.Bbb id=\"{1 + 2}abc\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "", expression: "{1 + 2}", text: "abc"]}]}
             ]
    end

    test "text, expression, text" do
      assert assemble("<Aaa.Bbb id=\"abc{1 + 2}xyz\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "abc", expression: "{1 + 2}", text: "xyz"]}]}
             ]
    end

    test "boolean property followed by whitespace" do
      assert assemble("<Aaa.Bbb my_prop >") == [start_tag: {"Aaa.Bbb", [{"my_prop", []}]}]
    end

    test "boolean property followed by start tag closing" do
      assert assemble("<Aaa.Bbb my_prop>") == [start_tag: {"Aaa.Bbb", [{"my_prop", []}]}]
    end

    test "multiple properties" do
      assert assemble("<Aaa.Bbb prop_1=\"value_1\" prop_2=\"value_2\">") == [
               start_tag:
                 {"Aaa.Bbb", [{"prop_1", [text: "value_1"]}, {"prop_2", [text: "value_2"]}]}
             ]
    end
  end

  describe "expression" do
    test "empty" do
      assert assemble("{}") == [expression: "{}"]
    end

    test "whitespaces" do
      assert assemble("{ \n\r\t}") == [expression: "{ \n\r\t}"]
    end

    test "string, ASCI alphabet lowercase" do
      markup = "{abcdefghijklmnopqrstuvwxyz}"
      assert assemble(markup) == [expression: markup]
    end

    test "string, ASCI alphabet uppercase" do
      markup = "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"
      assert assemble(markup) == [expression: markup]
    end

    test "string, UTF-8 chars" do
      markup = "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}"
      assert assemble(markup) == [expression: markup]
    end

    test "symbols" do
      markup = "{!@#$%^&*()-_=+[];:'\\\"\\|,./?`~}"
      assert assemble(markup) == [expression: markup]
    end

    test "single group of curly brackets" do
      markup = "{{123}}"
      assert assemble(markup) == [expression: markup]
    end

    test "multiple groups of curly brackets" do
      markup = "{{1},{2}}"
      assert assemble(markup) == [expression: markup]
    end

    test "opening curly bracket escaping" do
      markup = "{{\"\\{123\"}}"
      assert assemble(markup) == [expression: markup]
    end

    test "closing curly bracket escaping" do
      markup = "{{\"123\\}\"}}"
      assert assemble(markup) == [expression: markup]
    end

    test "single group of double quotes" do
      markup = "{{\"123\"}}"
      assert assemble(markup) == [expression: markup]
    end

    test "multiple groups of double quotes" do
      markup = "{{\"1\",\"2\"}}"
      assert assemble(markup) == [expression: markup]
    end

    test "double quote escaping" do
      markup = "{{1\\\"2}}"
      assert assemble(markup) == [expression: markup]
    end

    test "opening curly bracket inside double quoted string" do
      markup = "{{\"1\\{2\"}}"
      assert assemble(markup) == [expression: markup]
    end

    test "closing curly bracket inside double quoted string" do
      markup = "{{\"1\\}2\"}}"
      assert assemble(markup) == [expression: markup]
    end

    test "inside text" do
      assert assemble("abc{@kmn}xyz") == [text: "abc", expression: "{@kmn}", text: "xyz"]
    end

    test "inside element" do
      assert assemble("<div>{@abc}</div>") == [
               start_tag: {"div", []},
               expression: "{@abc}",
               end_tag: "div"
             ]
    end

    test "inside component" do
      assert assemble("<Aaa.Bbb>{@abc}</Aaa.Bbb>") == [
               start_tag: {"Aaa.Bbb", []},
               expression: "{@abc}",
               end_tag: "Aaa.Bbb"
             ]
    end
  end

  describe "block start" do
    test "without expression" do
      assert assemble("{#abc}") == [block_start: {"abc", "{}"}]
    end

    test "with whitespace expression" do
      assert assemble("{#abc \n\r\t}") == [block_start: {"abc", "{ \n\r\t}"}]
    end

    test "with non-whitespace expression" do
      assert assemble("{#if abc == {1, 2}}") == [block_start: {"if", "{ abc == {1, 2}}"}]
    end

    test "inside text" do
      assert assemble("abc{#kmn}xyz") == [text: "abc", block_start: {"kmn", "{}"}, text: "xyz"]
    end

    test "inside element" do
      assert assemble("<div>{#abc}</div>") == [
               start_tag: {"div", []},
               block_start: {"abc", "{}"},
               end_tag: "div"
             ]
    end

    test "inside component" do
      assert assemble("<Aaa.Bbb>{#abc}</Aaa.Bbb>") == [
               start_tag: {"Aaa.Bbb", []},
               block_start: {"abc", "{}"},
               end_tag: "Aaa.Bbb"
             ]
    end
  end

  describe "block end" do
    test "isolated" do
      assert assemble("{/abc}") == [block_end: "abc"]
    end

    test "inside text" do
      assert assemble("abc{/kmn}xyz") == [text: "abc", block_end: "kmn", text: "xyz"]
    end
  end

  describe "block" do
    test "single" do
      assert assemble("{#abc}{/abc}") == [block_start: {"abc", "{}"}, block_end: "abc"]
    end

    test "multiple, siblings" do
      assert assemble("{#abc}{/abc}{#xyz}{/xyz}") == [
               block_start: {"abc", "{}"},
               block_end: "abc",
               block_start: {"xyz", "{}"},
               block_end: "xyz"
             ]
    end

    test "multiple, nested" do
      assert assemble("{#abc}{#xyz}{/xyz}{/abc}") == [
               block_start: {"abc", "{}"},
               block_start: {"xyz", "{}"},
               block_end: "xyz",
               block_end: "abc"
             ]
    end
  end

  describe "raw block" do
    test "block start" do
      assert assemble("{#raw}") == []
    end

    test "block end" do
      assert assemble("{#raw}{/raw}") == []
    end

    test "with text" do
      assert assemble("{#raw}abc{/raw}") == [text: "abc"]
    end

    test "with element" do
      assert assemble("{#raw}<div></div>{/raw}") == [start_tag: {"div", []}, end_tag: "div"]
    end

    test "with component" do
      assert assemble("{#raw}<MyComponent></MyComponent>{/raw}") == [
               start_tag: {"MyComponent", []},
               end_tag: "MyComponent"
             ]
    end

    test "with expression" do
      assert assemble("{#raw}{1 + 2}{/raw}") == [text: "{1 + 2}"]
    end

    test "with expression nested in text" do
      assert assemble("{#raw}aaa{@test}bbb{/raw}") == [text: "aaa{@test}bbb"]
    end

    test "with template block" do
      assert assemble("{#raw}{#abc}{/abc}{/raw}") == [text: "{#abc}{/abc}"]
    end

    test "with '=' char nested in text" do
      assert assemble("{#raw}aaa = bbb{/raw}") == [text: "aaa = bbb"]
    end

    test "with '\"' char nested in text" do
      assert assemble("{#raw}aaa \" bbb{/raw}") == [text: "aaa \" bbb"]
    end

    test "with element having an attribute value with expression in double quotes" do
      assert assemble("{#raw}<div id=\"aaa{@test}bbb\"></div>{/raw}") == [
               start_tag: {"div", [{"id", [text: "aaa{@test}bbb"]}]},
               end_tag: "div"
             ]
    end

    test "with component having a property value with expression in double quotes" do
      assert assemble("{#raw}<Aaa.Bbb id=\"aaa{@test}bbb\"></Aaa.Bbb>{/raw}") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "aaa{@test}bbb"]}]},
               end_tag: "Aaa.Bbb"
             ]
    end

    test "inside text" do
      assert assemble("abc{#raw}{/raw}xyz") == [text: "abcxyz"]
    end

    test "inside element" do
      assert assemble("<div>{#raw}{/raw}</div>") == [start_tag: {"div", []}, end_tag: "div"]
    end

    test "inside component" do
      assert assemble("<MyComponent>{#raw}{/raw}</MyComponent>") == [
               start_tag: {"MyComponent", []},
               end_tag: "MyComponent"
             ]
    end
  end

  describe "script" do
    test "symbol '<' not inside double quoted string" do
      assert assemble("<script>1 < 2</script>") == [
               start_tag: {"script", []},
               text: "1 < 2",
               end_tag: "script"
             ]
    end

    test "symbol '<' inside double quoted string" do
      assert assemble("<script>\"1 < 2\"</script>") == [
               start_tag: {"script", []},
               text: "\"1 < 2\"",
               end_tag: "script"
             ]
    end

    test "symbol '>' not inside double quoted string" do
      assert assemble("<script>1 > 2</script>") == [
               start_tag: {"script", []},
               text: "1 > 2",
               end_tag: "script"
             ]
    end

    test "symbol '>' inside double quoted string" do
      assert assemble("<script>\"1 > 2\"</script>") == [
               start_tag: {"script", []},
               text: "\"1 > 2\"",
               end_tag: "script"
             ]
    end

    test "symbol '</' inside double quoted string" do
      assert assemble("<script>\"abc</xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc</xyz\"",
               end_tag: "script"
             ]
    end

    test "expression" do
      assert assemble("<script>const abc = {1 + 2};</script>") == [
               start_tag: {"script", []},
               text: "const abc = ",
               expression: "{1 + 2}",
               text: ";",
               end_tag: "script"
             ]
    end

    test "script end tag inside double quoted string" do
      assert assemble("<script>const abc = 'substr' + \"</script>\";</script>") == [
               start_tag: {"script", []},
               text: "const abc = 'substr' + \"</script>\";",
               end_tag: "script"
             ]
    end
  end

  describe "template syntax errors" do
    test "escape non-printable characters" do
      expected_msg = ~r/\na\\nb\\rc\\td < x\\ny\\rz\\tv\n {11}\^/s

      assert_raise SyntaxError, expected_msg, fn ->
        assemble("a\nb\rc\td < x\ny\rz\tv")
      end
    end

    test "strip excess characters" do
      expected_msg = ~r/\n2345678901234567890 < 1234567890123456789\n {20}\^/s

      assert_raise SyntaxError, expected_msg, fn ->
        assemble("123456789012345678901234567890 < 123456789012345678901234567890")
      end
    end

    test "unescaped '<' character inside text node" do
      expected_msg = """


      Reason:
      Unescaped '<' character inside text node.

      Hint:
      To escape use HTML entity: '&lt;'.

      abc < xyz
          ^

      status = :text

      token = {:symbol, "<"}

      context = %{attr_name: nil, attr_value: [], attrs: [], block_expression: nil, block_name: nil, double_quote_open?: false, node_type: :text, num_open_curly_brackets: 0, prev_status: nil, processed_tags: [], processed_tokens: [string: "abc", whitespace: " "], raw?: false, script?: false, tag_name: nil, token_buffer: [string: "abc", whitespace: " "]}
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble("abc < xyz")
      end
    end

    test "unescaped '>' character inside text node" do
      expected_msg = """


      Reason:
      Unescaped '>' character inside text node.

      Hint:
      To escape use HTML entity: '&gt;'.

      abc > xyz
          ^

      status = :text

      token = {:symbol, ">"}

      context = %{attr_name: nil, attr_value: [], attrs: [], block_expression: nil, block_name: nil, double_quote_open?: false, node_type: :text, num_open_curly_brackets: 0, prev_status: nil, processed_tags: [], processed_tokens: [string: "abc", whitespace: " "], raw?: false, script?: false, tag_name: nil, token_buffer: [string: "abc", whitespace: " "]}
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble("abc > xyz")
      end
    end

    test "expression attribute value inside raw block" do
      expected_msg = """


      Reason:
      Expression attribute value inside raw block detected.

      Hint:
      Either wrap the attribute value with double quotes or remove the parent raw block".

      {#raw}<div id={@abc}></div>{/raw}
                    ^

      status = :attr_assignment

      token = {:symbol, "{"}

      context = %{attr_name: "id", attr_value: [], attrs: [], block_expression: nil, block_name: nil, double_quote_open?: false, node_type: :attribute, num_open_curly_brackets: 0, prev_status: :attr_name, processed_tags: [], processed_tokens: [symbol: "{#raw}", symbol: "<", string: "div", whitespace: " ", string: "id", symbol: "="], raw?: true, script?: false, tag_name: "div", token_buffer: []}
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble("{#raw}<div id={@abc}></div>{/raw}")
      end
    end

    test "expression property value inside raw block" do
      expected_msg = """


      Reason:
      Expression property value inside raw block detected.

      Hint:
      Either wrap the property value with double quotes or remove the parent raw block".

      {#raw}<Aa.Bb id={@abc}></Aa.Bb>{/raw}
                      ^

      status = :attr_assignment

      token = {:symbol, "{"}

      context = %{attr_name: "id", attr_value: [], attrs: [], block_expression: nil, block_name: nil, double_quote_open?: false, node_type: :attribute, num_open_curly_brackets: 0, prev_status: :attr_name, processed_tags: [], processed_tokens: [symbol: "{#raw}", symbol: "<", string: "Aa.Bb", whitespace: " ", string: "id", symbol: "="], raw?: true, script?: false, tag_name: "Aa.Bb", token_buffer: []}
      """

      assert_raise SyntaxError, expected_msg, fn ->
        assemble("{#raw}<Aa.Bb id={@abc}></Aa.Bb>{/raw}")
      end
    end
  end

  # TODO: cleanup

  # describe "text node nested in raw directive" do
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
