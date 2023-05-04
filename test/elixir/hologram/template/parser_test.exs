defmodule Hologram.Template.ParserTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Template.Parser
  alias Hologram.Template.SyntaxError
  alias Hologram.Template.Tokenizer

  # Except: { } " ' ` \ < >
  @special_chars [
    " ",
    "\n",
    "\r",
    "\t",
    "!",
    "@",
    "#",
    "$",
    "%",
    "^",
    "&",
    "*",
    "(",
    ")",
    "-",
    "_",
    "=",
    "+",
    "[",
    "]",
    ";",
    ":",
    "|",
    "~",
    ",",
    ".",
    "/",
    "?"
  ]

  defp parse(markup) do
    markup
    |> Tokenizer.tokenize()
    |> Parser.parse()
  end

  defp test_syntax_error_msg(markup, msg) do
    assert_raise SyntaxError, ~r/#{Regex.escape(msg)}/s, fn ->
      parse(markup)
    end
  end

  describe "text" do
    test "empty" do
      assert parse("") == []
    end

    test "with whitespaces" do
      markup = " \n\r\t"
      assert parse(markup) == [text: markup]
    end

    test "with symbols" do
      markup = "#$%"
      assert parse(markup) == [text: markup]
    end

    test "with string" do
      markup = "abc"
      assert parse(markup) == [text: markup]
    end
  end

  describe "element tags" do
    test "non-void HTML element start tag" do
      assert parse("<div>") == [start_tag: {"div", []}]
    end

    test "non-void SVG element start tag" do
      assert parse("<g>") == [start_tag: {"g", []}]
    end

    test "void HTML element, unclosed start tag" do
      assert parse("<br>") == [self_closing_tag: {"br", []}]
    end

    test "void HTML element, self-closed start tag" do
      assert parse("<br />") == [self_closing_tag: {"br", []}]
    end

    test "void SVG element, unclosed start tag" do
      assert parse("<path>") == [self_closing_tag: {"path", []}]
    end

    test "void SVG element, self-closed start tag" do
      assert parse("<path />") == [self_closing_tag: {"path", []}]
    end

    test "slot element, unclosed start tag" do
      assert parse("<slot>") == [self_closing_tag: {"slot", []}]
    end

    test "slot element, self-closed start tag" do
      assert parse("<slot />") == [self_closing_tag: {"slot", []}]
    end

    test "whitespaces after unclosed start tag name" do
      assert parse("<div \n\r\t>") == [start_tag: {"div", []}]
    end

    test "end tag" do
      assert parse("</div>") == [end_tag: "div"]
    end

    test "whitespaces after end tag name" do
      assert parse("</div \n\r\t>") == [end_tag: "div"]
    end
  end

  describe "component tags" do
    test "unclosed start tag" do
      assert parse("<Aaa.Bbb>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "self-closed start tag" do
      assert parse("<Aaa.Bbb />") == [self_closing_tag: {"Aaa.Bbb", []}]
    end

    test "whitespaces after unclosed start tag name" do
      assert parse("<Aaa.Bbb \n\r\t>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "end tag" do
      assert parse("</Aaa.Bbb>") == [end_tag: "Aaa.Bbb"]
    end

    test "whitespaces after end tag name" do
      assert parse("</Aaa.Bbb \n\r\t>") == [end_tag: "Aaa.Bbb"]
    end
  end

  describe "expression" do
    test "empty" do
      assert parse("{}") == [expression: "{}"]
    end

    test "with whitespaces" do
      markup = "{ \n\r\t}"
      assert parse(markup) == [expression: markup]
    end

    test "with symbols" do
      markup = "{#$%}"
      assert parse(markup) == [expression: markup]
    end

    test "with string" do
      markup = "{abc}"
      assert parse(markup) == [expression: markup]
    end
  end

  describe "element attribute and component property" do
    [{"attribute", "div"}, {"property", "Aaa.Bbb"}]
    |> Enum.each(fn {name, tag} ->
      test "#{name} value text" do
        assert parse("<#{unquote(tag)} id=\"test\">") == [
                 start_tag: {unquote(tag), [{"id", [text: "test"]}]}
               ]
      end

      test "#{name} value expression" do
        assert parse("<#{unquote(tag)} id={1 + 2}>") == [
                 start_tag: {unquote(tag), [{"id", [expression: "{1 + 2}"]}]}
               ]
      end

      test "#{name} value expression in double quotes" do
        assert parse("<#{unquote(tag)} id=\"{1 + 2}\">") == [
                 start_tag: {unquote(tag), [{"id", [text: "", expression: "{1 + 2}", text: ""]}]}
               ]
      end

      test "multi-part #{name} value: text, expression" do
        assert parse("<#{unquote(tag)} id=\"abc{1 + 2}\">") == [
                 start_tag:
                   {unquote(tag), [{"id", [text: "abc", expression: "{1 + 2}", text: ""]}]}
               ]
      end

      test "multi-part #{name} value: expression, text" do
        assert parse("<#{unquote(tag)} id=\"{1 + 2}abc\">") == [
                 start_tag:
                   {unquote(tag), [{"id", [text: "", expression: "{1 + 2}", text: "abc"]}]}
               ]
      end

      test "boolean #{name} followed by start tag closing" do
        assert parse("<#{unquote(tag)} key>") == [start_tag: {unquote(tag), [{"key", []}]}]
      end

      test "multiple #{name}(s)" do
        assert parse(~s(<#{unquote(tag)} key_1="value_1" key_2="value_2">)) == [
                 start_tag:
                   {unquote(tag), [{"key_1", [text: "value_1"]}, {"key_2", [text: "value_2"]}]}
               ]
      end
    end)
  end

  describe "for block" do
    test "start" do
      markup = "{%for item <- @items}"
      assert parse(markup) == [block_start: {"for", "{ item <- @items}"}]
    end

    test "end" do
      assert parse("{/for}") == [block_end: "for"]
    end
  end

  describe "if block" do
    test "start" do
      markup = "{%if true}"
      assert parse(markup) == [block_start: {"if", "{ true}"}]
    end

    test "end" do
      assert parse("{/if}") == [block_end: "if"]
    end
  end

  describe "raw block" do
    test "empty" do
      assert parse("{%raw}{/raw}") == []
    end

    test "with whitespaces" do
      markup = " \n\r\t"
      assert parse("{%raw}#{markup}{/raw}") == [text: markup]
    end

    test "with symbols" do
      markup = "#$%"
      assert parse("{%raw}#{markup}{/raw}") == [text: markup]
    end

    test "with string" do
      markup = "abc"
      assert parse("{%raw}#{markup}{/raw}") == [text: markup]
    end

    test "with element having an attribute value with expression in double quotes" do
      assert parse("{%raw}<div id=\"aaa{@test}bbb\"></div>{/raw}") == [
               start_tag: {"div", [{"id", [text: "aaa{@test}bbb"]}]},
               end_tag: "div"
             ]
    end

    test "with component having a property value with expression in double quotes" do
      assert parse("{%raw}<Aaa.Bbb id=\"aaa{@test}bbb\"></Aaa.Bbb>{/raw}") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "aaa{@test}bbb"]}]},
               end_tag: "Aaa.Bbb"
             ]
    end

    test "with script" do
      assert parse("{%raw}<script>{@abc}</script>{/raw}") == [
               start_tag: {"script", []},
               text: "{@abc}",
               end_tag: "script"
             ]
    end

    test "within script" do
      assert parse("<script>{%raw}{@abc}{/raw}</script>") == [
               start_tag: {"script", []},
               text: "{@abc}",
               end_tag: "script"
             ]
    end
  end

  describe "raw block with nested tag not using curly bracket" do
    tags = [
      {"text", "abc", text: "abc"},
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"}
    ]

    Enum.each(tags, fn {name, markup, expected} ->
      test "raw block start, #{name}, raw block end" do
        assert parse("{%raw}#{unquote(markup)}{/raw}") == unquote(expected)
      end
    end)
  end

  describe "raw block with nested tag using curly brackets" do
    tags = [
      {"expression", "{@abc}"},
      {"for block start", "{%for item &lt;- @items}"},
      {"for block end", "{/for}"},
      {"if block start", "{%if true}"},
      {"if block end", "{/if}"}
    ]

    Enum.each(tags, fn {name, markup} ->
      test "raw block start, #{name}, raw block end" do
        assert parse("{%raw}#{unquote(markup)}{/raw}") == [text: unquote(markup)]
      end
    end)
  end

  describe "raw block nested in quotes" do
    test "inside double quotes within elixir expression" do
      markup = "{\"{%raw}{@abc}{/raw}\"}"
      assert parse(markup) == [expression: markup]
    end

    test "inside single quotes within elixir expression" do
      markup = "{'{%raw}{@abc}{/raw}'}"
      assert parse(markup) == [expression: markup]
    end

    test "inside double quotes within javascript script" do
      markup = "<script>\"{%raw}{@abc}{/raw}\"</script>"
      assert parse(markup) == [start_tag: {"script", []}, text: "\"{@abc}\"", end_tag: "script"]
    end

    test "inside single quotes within javascript script" do
      markup = "<script>'{%raw}{@abc}{/raw}'</script>"
      assert parse(markup) == [start_tag: {"script", []}, text: "'{@abc}'", end_tag: "script"]
    end

    test "inside backtick quotes within javascript script" do
      markup = "<script>`{%raw}{@abc}{/raw}`</script>"
      assert parse(markup) == [start_tag: {"script", []}, text: "`{@abc}`", end_tag: "script"]
    end
  end

  describe "row block after" do
    tags = [
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"},
      {"expression", "{@abc}", expression: "{@abc}"},
      {"for block start", "{%for item <- @items}", block_start: {"for", "{ item <- @items}"}},
      {"for block end", "{/for}", block_end: "for"},
      {"if block start", "{%if true}", block_start: {"if", "{ true}"}},
      {"if block end", "{/if}", block_end: "if"}
    ]

    Enum.each(tags, fn {name, markup, [expected]} ->
      test "#{name}" do
        assert parse("#{unquote(markup)}{%raw}{@abc}{/raw}") == [
                 unquote(expected),
                 {:text, "{@abc}"}
               ]
      end
    end)

    test "text" do
      assert parse("abc{%raw}{@abc}{/raw}") == [text: "abc{@abc}"]
    end
  end

  describe "tag combinations other than raw block" do
    tags = [
      {"text", "abc", text: "abc"},
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"},
      {"expression", "{@abc}", expression: "{@abc}"},
      {"for block start", "{%for item <- @items}", block_start: {"for", "{ item <- @items}"}},
      {"for block end", "{/for}", block_end: "for"},
      {"if block start", "{%if true}", block_start: {"if", "{ true}"}},
      {"if block end", "{/if}", block_end: "if"}
    ]

    for(tag_1 <- tags, tag_2 <- tags, do: {tag_1, tag_2})
    |> Enum.reject(fn {{name_1, _markup_1, [_expected_1]}, {name_2, _markup_2, [_expected_2]}} ->
      name_1 == "text" && name_2 == "text"
    end)
    |> Enum.each(fn {{name_1, markup_1, [expected_1]}, {name_2, markup_2, [expected_2]}} ->
      test "#{name_1}, #{name_2}" do
        assert parse("#{unquote(markup_1)}#{unquote(markup_2)}") == [
                 unquote(expected_1),
                 unquote(expected_2)
               ]
      end
    end)
  end

  # Test special chararacters nested in various markup.
  Enum.each(@special_chars, fn char ->
    describe "'#{char}' character" do
      test "in text" do
        assert parse(unquote(char)) == [text: unquote(char)]
      end

      test "in text interpolated expression" do
        markup = "{#{unquote(char)}}"
        assert parse(markup) == [expression: markup]
      end

      test "in attribute value text part" do
        markup = "<div my_attr=\"#{unquote(char)}\">"
        assert parse(markup) == [start_tag: {"div", [{"my_attr", [text: unquote(char)]}]}]
      end

      test "in attribute value expression part" do
        markup = "<div my_attr={#{unquote(char)}}>"

        assert parse(markup) == [
                 start_tag: {"div", [{"my_attr", [expression: "{#{unquote(char)}}"]}]}
               ]
      end

      test "in for block expression" do
        markup = "{%for #{unquote(char)}}{/for}"

        assert parse(markup) == [
                 block_start: {"for", "{ #{unquote(char)}}"},
                 block_end: "for"
               ]
      end

      test "in for block content" do
        markup = "{%for item <- @items}#{unquote(char)}{/for}"

        assert parse(markup) == [
                 block_start: {"for", "{ item <- @items}"},
                 text: "#{unquote(char)}",
                 block_end: "for"
               ]
      end

      test "in if block expression" do
        markup = "{%if #{unquote(char)}}{/if}"

        assert parse(markup) == [
                 block_start: {"if", "{ #{unquote(char)}}"},
                 block_end: "if"
               ]
      end

      test "in if block content" do
        markup = "{%if true}#{unquote(char)}{/if}"

        assert parse(markup) == [
                 block_start: {"if", "{ true}"},
                 text: "#{unquote(char)}",
                 block_end: "if"
               ]
      end

      test "in raw block content" do
        markup = "{%raw}#{unquote(char)}{/raw}"
        assert parse(markup) == [text: "#{unquote(char)}"]
      end

      test "in script" do
        markup = "<script>#{unquote(char)}</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "#{unquote(char)}",
                 end_tag: "script"
               ]
      end
    end
  end)

  # Test start and end tags nested in various markup.
  Enum.each(
    [
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"}
    ],
    fn {name, markup, [expected]} ->
      describe "#{name} inside" do
        test "text" do
          assert parse("abc#{unquote(markup)}xyz") == [
                   {:text, "abc"},
                   unquote(expected),
                   {:text, "xyz"}
                 ]
        end

        test "for block" do
          assert parse("{%for item <- @items}#{unquote(markup)}{/for}") == [
                   {:block_start, {"for", "{ item <- @items}"}},
                   unquote(expected),
                   {:block_end, "for"}
                 ]
        end

        test "if block" do
          assert parse("{%if true}#{unquote(markup)}{/if}") == [
                   {:block_start, {"if", "{ true}"}},
                   unquote(expected),
                   {:block_end, "if"}
                 ]
        end

        test "elixir expression double quoted string" do
          assert parse("{\"#{unquote(markup)}\"}") == [expression: "{\"#{unquote(markup)}\"}"]
        end

        test "elixir expression single quoted string" do
          assert parse("{'#{unquote(markup)}'}") == [expression: "{'#{unquote(markup)}'}"]
        end

        test "javascript script double quoted string" do
          assert parse("<script>\"#{unquote(markup)}\"</script>") == [
                   start_tag: {"script", []},
                   text: "\"#{unquote(markup)}\"",
                   end_tag: "script"
                 ]
        end

        test "javascript script single quoted string" do
          assert parse("<script>'#{unquote(markup)}'</script>") == [
                   start_tag: {"script", []},
                   text: "'#{unquote(markup)}'",
                   end_tag: "script"
                 ]
        end

        test "javascript script backtick quoted string" do
          assert parse("<script>`#{unquote(markup)}`</script>") == [
                   start_tag: {"script", []},
                   text: "`#{unquote(markup)}`",
                   end_tag: "script"
                 ]
        end
      end
    end
  )

  # Test block starts and ends nested inside quotes within various markup.
  Enum.each([{"for", "item <- @items"}, {"if", "true"}], fn {name, expression} ->
    describe "nested #{name}" do
      test "block start inside double quotes within elixir expression" do
        markup = "{\"{%#{unquote(name)} #{unquote(expression)}}\"}"
        assert parse(markup) == [expression: markup]
      end

      test "block end inside double quotes within elixir expression" do
        markup = "{\"{/#{unquote(name)}}\"}"
        assert parse(markup) == [expression: markup]
      end

      test "block start inside single quotes within elixir expression" do
        markup = "{'{%#{unquote(name)} #{unquote(expression)}}'}"
        assert parse(markup) == [expression: markup]
      end

      test "block end inside single quotes within elixir expression" do
        markup = "{'{/#{unquote(name)}}'}"
        assert parse(markup) == [expression: markup]
      end

      test "block start inside double quotes within javascript script" do
        markup = "<script>\"{%#{unquote(name)} #{unquote(expression)}}\"</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "\"",
                 block_start: {unquote(name), "{ #{unquote(expression)}}"},
                 text: "\"",
                 end_tag: "script"
               ]
      end

      test "block end inside double quotes within javascript script" do
        markup = "<script>\"{/#{unquote(name)}}\"</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "\"",
                 block_end: unquote(name),
                 text: "\"",
                 end_tag: "script"
               ]
      end

      test "block start inside single quotes within javascript script" do
        markup = "<script>'{%#{unquote(name)} #{unquote(expression)}}'</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "'",
                 block_start: {unquote(name), "{ #{unquote(expression)}}"},
                 text: "'",
                 end_tag: "script"
               ]
      end

      test "block end inside single quotes within javascript script" do
        markup = "<script>'{/#{unquote(name)}}'</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "'",
                 block_end: unquote(name),
                 text: "'",
                 end_tag: "script"
               ]
      end

      test "block start inside backtick quotes within javascript script" do
        markup = "<script>`{%#{unquote(name)} #{unquote(expression)}}`</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "`",
                 block_start: {unquote(name), "{ #{unquote(expression)}}"},
                 text: "`",
                 end_tag: "script"
               ]
      end

      test "block end inside backtick quotes within javascript script" do
        markup = "<script>`{/#{unquote(name)}}`</script>"

        assert parse(markup) == [
                 start_tag: {"script", []},
                 text: "`",
                 block_end: unquote(name),
                 text: "`",
                 end_tag: "script"
               ]
      end
    end
  end)

  describe "elixir interpolation" do
    test "in text" do
      markup = "\#{@abc}"
      assert parse(markup) == [text: markup]
    end

    test "in expression, inside double quotes" do
      markup = "{\"aaa\#{123}bbb\"}"
      assert parse(markup) == [expression: "{\"aaa\#{123}bbb\"}"]
    end

    test "in expression, inside single quotes" do
      markup = "{'aaa\#{123}bbb'}"
      assert parse(markup) == [expression: "{'aaa\#{123}bbb'}"]
    end

    test "in expression, nested inside double quotes and then inside double quotes" do
      markup = "{\"aaa\#{\"bbb\#{123}ccc\"}ddd\"}"
      assert parse(markup) == [expression: "{\"aaa\#{\"bbb\#{123}ccc\"}ddd\"}"]
    end

    test "in expression, nested inside single quotes and then inside single quotes" do
      markup = "{'aaa\#{'bbb\#{123}ccc'}ddd'}"
      assert parse(markup) == [expression: "{'aaa\#{'bbb\#{123}ccc'}ddd'}"]
    end

    test "in expression, nested inside double quotes and then inside single quotes" do
      markup = "{\"aaa\#{'bbb\#{123}ccc'}ddd\"}"
      assert parse(markup) == [expression: "{\"aaa\#{'bbb\#{123}ccc'}ddd\"}"]
    end

    test "in expression, nested inside single quotes and then inside double quotes" do
      markup = "{'aaa\#{\"bbb\#{123}ccc\"}ddd'}"
      assert parse(markup) == [expression: "{'aaa\#{\"bbb\#{123}ccc\"}ddd'}"]
    end

    test "in attribute value text part" do
      markup = "<div my_attr=\"\#{@abc}\">"
      assert parse(markup) == [start_tag: {"div", [{"my_attr", [text: "\#{@abc}"]}]}]
    end

    test "in attribute value expression part" do
      markup = "<div my_attr={\"\#{@abc}\"}>"

      assert parse(markup) == [
               start_tag: {"div", [{"my_attr", [expression: "{\"\#{@abc}\"}"]}]}
             ]
    end

    test "in for block expression" do
      markup = "{%for item <- [\"\#{@abc}\"]}{/for}"

      assert parse(markup) == [
               block_start: {"for", "{ item <- [\"\#{@abc}\"]}"},
               block_end: "for"
             ]
    end

    test "in if block expression" do
      markup = "{%if \"\#{@abc}\"}{/if}"

      assert parse(markup) == [
               block_start: {"if", "{ \"\#{@abc}\"}"},
               block_end: "if"
             ]
    end

    test "in raw block" do
      markup = "{%raw}\#{@abc}{/raw}"
      assert parse(markup) == [text: "\#{@abc}"]
    end

    test "in script" do
      markup = "<script>\#{@abc}</script>"
      assert parse(markup) == [start_tag: {"script", []}, text: "\#{@abc}", end_tag: "script"]
    end
  end

  describe "template syntax errors" do
    test "escape non-printable characters" do
      expected_msg = ~r/\na\\nb\\rc\\td < x\\ny\\rz\\tv\n {11}\^/s

      assert_raise SyntaxError, expected_msg, fn ->
        parse("a\nb\rc\td < x\ny\rz\tv")
      end
    end

    test "strip excess characters" do
      expected_msg = ~r/\n2345678901234567890 < 1234567890123456789\n {20}\^/s

      assert_raise SyntaxError, expected_msg, fn ->
        parse("123456789012345678901234567890 < 123456789012345678901234567890")
      end
    end

    test "unescaped '<' character inside text node" do
      msg = """
      Reason:
      Unescaped '<' character inside text node.

      Hint:
      To escape use HTML entity: '&lt;'.

      abc < xyz
          ^
      """

      test_syntax_error_msg("abc < xyz", msg)
    end

    test "unescaped '>' character inside text node" do
      msg = """
      Reason:
      Unescaped '>' character inside text node.

      Hint:
      To escape use HTML entity: '&gt;'.

      abc > xyz
          ^
      """

      test_syntax_error_msg("abc > xyz", msg)
    end

    test "expression attribute value inside raw block" do
      msg = """
      Reason:
      Expression attribute value inside raw block detected.

      Hint:
      Either wrap the attribute value with double quotes or remove the parent raw block".

      {%raw}<div id={@abc}></div>{/raw}
                    ^
      """

      test_syntax_error_msg("{%raw}<div id={@abc}></div>{/raw}", msg)
    end

    test "expression property value inside raw block" do
      msg = """
      Reason:
      Expression property value inside raw block detected.

      Hint:
      Either wrap the property value with double quotes or remove the parent raw block".

      {%raw}<Aa.Bb id={@abc}></Aa.Bb>{/raw}
                      ^
      """

      test_syntax_error_msg("{%raw}<Aa.Bb id={@abc}></Aa.Bb>{/raw}", msg)
    end

    test "unclosed start tag" do
      msg = """
      Reason:
      Unclosed start tag.

      Hint:
      Close the start tag with '>' character.

      <div
          ^
      """

      test_syntax_error_msg("<div", msg)
    end

    test "missing attribute name" do
      msg = """
      Reason:
      Missing attribute name.

      Hint:
      Specify the attribute name before the '=' character.

      <div ="abc">
           ^
      """

      test_syntax_error_msg("<div =\"abc\">", msg)
    end
  end

  #   test "double quote escaping" do
  #     markup = "{{1\\\"2}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "single quote escaping" do
  #     markup = "{{1\\\'2}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "inside text" do
  #     assert parse("abc{@kmn}xyz") == [text: "abc", expression: "{@kmn}", text: "xyz"]
  #   end

  #   test "single group of curly brackets" do
  #     markup = "{{123}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "multiple groups of curly brackets" do
  #     markup = "{{1}, {2}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "opening curly bracket inside double quotes" do
  #     markup = "{{\"{123\"}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "opening curly bracket inside single quotes" do
  #     markup = "{{'{123'}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "closing curly bracket inside double quotes" do
  #     markup = "{{\"123}\"}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "closing curly bracket inside single quotes" do
  #     markup = "{{'123}'}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "single group of double quotes" do
  #     markup = "{{\"123\"}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "multiple groups of double quotes" do
  #     markup = "{{\"1\", \"2\"}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "single group of single quotes" do
  #     markup = "{{'123'}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "multiple groups of single quotes" do
  #     markup = "{{'1', '2'}}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "single quote nested in double quotes" do
  #     markup = "{\"abc'xyz\"}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "double quote nested in single quotes" do
  #     markup = "{'abc\"xyz'}"
  #     assert parse(markup) == [expression: markup]
  #   end

  #   test "opening curly bracket escaping" do
  #     assert parse("abc\\{xyz") == [text: "abc{xyz"]
  #   end

  #   test "closing curly bracket escaping" do
  #     assert parse("abc\\}xyz") == [text: "abc}xyz"]
  #   end

  # describe "script" do
  #   test "single group of double quotes" do
  #     assert parse("<script>\"abc\"</script>") == [
  #              start_tag: {"script", []},
  #              text: "\"abc\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "multiple groups of double quotes" do
  #     assert parse(~s(<script>"abc" + "xyz"</script>)) == [
  #              start_tag: {"script", []},
  #              text: "\"abc\" + \"xyz\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "single group of single quotes" do
  #     assert parse("<script>'abc'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'abc'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "multiple groups of single quotes" do
  #     assert parse("<script>'abc' + 'xyz'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'abc' + 'xyz'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "single group of backticks" do
  #     assert parse("<script>`abc`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`abc`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "multiple groups of backticks" do
  #     assert parse("<script>`abc` + `xyz`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`abc` + `xyz`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '<' not inside delimiters" do
  #     assert parse("<script>1 < 2</script>") == [
  #              start_tag: {"script", []},
  #              text: "1 < 2",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '<' inside double quotes" do
  #     assert parse("<script>\"1 < 2\"</script>") == [
  #              start_tag: {"script", []},
  #              text: "\"1 < 2\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '<' inside single quotes" do
  #     assert parse("<script>'1 < 2'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'1 < 2'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '<' inside backticks" do
  #     assert parse("<script>`1 < 2`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`1 < 2`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '>' not inside delimiters" do
  #     assert parse("<script>1 > 2</script>") == [
  #              start_tag: {"script", []},
  #              text: "1 > 2",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '>' inside double quotes" do
  #     assert parse("<script>\"1 > 2\"</script>") == [
  #              start_tag: {"script", []},
  #              text: "\"1 > 2\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '>' inside single quotes" do
  #     assert parse("<script>'1 > 2'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'1 > 2'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '>' inside backticks" do
  #     assert parse("<script>`1 > 2`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`1 > 2`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '</' inside double quotes" do
  #     assert parse("<script>\"abc</xyz\"</script>") == [
  #              start_tag: {"script", []},
  #              text: "\"abc</xyz\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '</' inside single quotes" do
  #     assert parse("<script>'abc</xyz'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'abc</xyz'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "symbol '</' inside backticks" do
  #     assert parse("<script>`abc</xyz`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`abc</xyz`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "double quote nested in single quotes" do
  #     assert parse("<script>'abc\"xyz'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'abc\"xyz'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "double quote nested in backticks" do
  #     assert parse("<script>`abc\"xyz`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`abc\"xyz`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "single quote nested in double quotes" do
  #     assert parse("<script>\"abc'xyz\"</script>") == [
  #              start_tag: {"script", []},
  #              text: "\"abc'xyz\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "single quote nested in backticks" do
  #     assert parse("<script>`abc'xyz`</script>") == [
  #              start_tag: {"script", []},
  #              text: "`abc'xyz`",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "backtick nested in double quotes" do
  #     assert parse("<script>\"abc`xyz\"</script>") == [
  #              start_tag: {"script", []},
  #              text: "\"abc`xyz\"",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "backtick nested in single quotes" do
  #     assert parse("<script>'abc`xyz'</script>") == [
  #              start_tag: {"script", []},
  #              text: "'abc`xyz'",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "script end tag inside double quotes" do
  #     assert parse("<script>const abc = 'substr' + \"</script>\";</script>") == [
  #              start_tag: {"script", []},
  #              text: "const abc = 'substr' + \"</script>\";",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "script end tag inside single quotes" do
  #     assert parse("<script>const abc = 'substr' + '</script>';</script>") == [
  #              start_tag: {"script", []},
  #              text: "const abc = 'substr' + '</script>';",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "script end tag inside backticks" do
  #     assert parse("<script>const abc = 'substr' + `</script>`;</script>") == [
  #              start_tag: {"script", []},
  #              text: "const abc = 'substr' + `</script>`;",
  #              end_tag: "script"
  #            ]
  #   end

  #   test "expression" do
  #     assert parse("<script>const abc = {1 + 2};</script>") == [
  #              start_tag: {"script", []},
  #              text: "const abc = ",
  #              expression: "{1 + 2}",
  #              text: ";",
  #              end_tag: "script"
  #            ]
  #   end
  # end

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

  #   #   result = parse(markup)
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

  # #   result = parse(markup)
  # #   IO.inspect(result)
  # #   # expected = [text: "aaabbb"]

  # #   # assert result == expected
  # # end
end
