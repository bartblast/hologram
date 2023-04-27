defmodule Hologram.Template.ParserTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Template.Parser
  alias Hologram.Template.SyntaxError
  alias Hologram.Template.Tokenizer

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

    test "whitespaces" do
      markup = " \n\r\t"
      assert parse(markup) == [text: markup]
    end

    test "string, ASCI alphabet lowercase" do
      markup = "abcdefghijklmnopqrstuvwxyz"
      assert parse(markup) == [text: markup]
    end

    test "string, ASCI alphabet uppercase" do
      markup = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      assert parse(markup) == [text: markup]
    end

    test "string, UTF-8 chars" do
      markup = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"
      assert parse(markup) == [text: markup]
    end

    test "symbols" do
      markup = "!@$%^&*()-_=+[];:'\"\\|,./?`~"
      assert parse(markup) == [text: markup]
    end

    test "opening curly bracket escaping" do
      assert parse("abc\\{xyz") == [text: "abc{xyz"]
    end

    test "closing curly bracket escaping" do
      assert parse("abc\\}xyz") == [text: "abc}xyz"]
    end

    test "ended by element start tag" do
      assert parse("abc<div>") == [text: "abc", start_tag: {"div", []}]
    end

    test "ended by component start tag" do
      assert parse("abc<Aaa.Bbb>") == [text: "abc", start_tag: {"Aaa.Bbb", []}]
    end

    test "ended by element end tag" do
      assert parse("abc</div>") == [text: "abc", end_tag: "div"]
    end

    test "ended by component end tag" do
      assert parse("abc</Aaa.Bbb>") == [text: "abc", end_tag: "Aaa.Bbb"]
    end

    test "ended by block start" do
      assert parse("abc{#xyz}") == [text: "abc", block_start: {"xyz", "{}"}]
    end
  end

  describe "start tag" do
    test "non-void HTML element" do
      assert parse("<div>") == [start_tag: {"div", []}]
    end

    test "non-void SVG element" do
      assert parse("<g>") == [start_tag: {"g", []}]
    end

    test "void HTML element, unclosed" do
      assert parse("<br>") == [self_closing_tag: {"br", []}]
    end

    test "void HTML element, self-closed" do
      assert parse("<br />") == [self_closing_tag: {"br", []}]
    end

    test "void SVG element, unclosed" do
      assert parse("<path>") == [self_closing_tag: {"path", []}]
    end

    test "void SVG element, self-closed" do
      assert parse("<path />") == [self_closing_tag: {"path", []}]
    end

    test "slot element, unclosed" do
      assert parse("<slot>") == [self_closing_tag: {"slot", []}]
    end

    test "slot element, self-closed" do
      assert parse("<slot />") == [self_closing_tag: {"slot", []}]
    end

    test "component, unclosed" do
      assert parse("<Aaa.Bbb>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "component, self-closed" do
      assert parse("<Aaa.Bbb />") == [self_closing_tag: {"Aaa.Bbb", []}]
    end

    test "whitespace after element tag name" do
      assert parse("<div \n\r\t>") == [start_tag: {"div", []}]
    end

    test "whitespace after component tag name" do
      assert parse("<Aaa.Bbb \n\r\t>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "inside text, element" do
      assert parse("abc<div>xyz") == [text: "abc", start_tag: {"div", []}, text: "xyz"]
    end

    test "inside text, component" do
      assert parse("abc<Aaa.Bbb>xyz") == [text: "abc", start_tag: {"Aaa.Bbb", []}, text: "xyz"]
    end
  end

  describe "end tag" do
    test "element" do
      assert parse("</div>") == [end_tag: "div"]
    end

    test "component" do
      assert parse("</Aaa.Bbb>") == [end_tag: "Aaa.Bbb"]
    end

    test "whitespace after element tag name" do
      assert parse("</div \n\r\t>") == [end_tag: "div"]
    end

    test "whitespace after component tag name" do
      assert parse("</Aaa.Bbb \n\r\t>") == [end_tag: "Aaa.Bbb"]
    end

    test "inside text, element" do
      assert parse("abc</div>xyz") == [text: "abc", end_tag: "div", text: "xyz"]
    end

    test "inside text, component" do
      assert parse("abc</Aaa.Bbb>xyz") == [text: "abc", end_tag: "Aaa.Bbb", text: "xyz"]
    end
  end

  describe "element" do
    test "single" do
      assert parse("<div></div>") == [start_tag: {"div", []}, end_tag: "div"]
    end

    test "multiple, siblings" do
      assert parse("<span></span><button></button>") == [
               start_tag: {"span", []},
               end_tag: "span",
               start_tag: {"button", []},
               end_tag: "button"
             ]
    end

    test "multiple, nested" do
      assert parse("<div><span></span></div>") == [
               start_tag: {"div", []},
               start_tag: {"span", []},
               end_tag: "span",
               end_tag: "div"
             ]
    end
  end

  describe "component" do
    test "single" do
      assert parse("<Aaa.Bbb></Aaa.Bbb>") == [start_tag: {"Aaa.Bbb", []}, end_tag: "Aaa.Bbb"]
    end

    test "multiple, siblings" do
      assert parse("<Aaa.Bbb></Aaa.Bbb><Eee.Fff></Eee.Fff>") == [
               start_tag: {"Aaa.Bbb", []},
               end_tag: "Aaa.Bbb",
               start_tag: {"Eee.Fff", []},
               end_tag: "Eee.Fff"
             ]
    end

    test "multiple, nested" do
      assert parse("<Aaa.Bbb><Eee.Fff></Eee.Fff></Aaa.Bbb>") == [
               start_tag: {"Aaa.Bbb", []},
               start_tag: {"Eee.Fff", []},
               end_tag: "Eee.Fff",
               end_tag: "Aaa.Bbb"
             ]
    end
  end

  describe "attribute" do
    test "text" do
      assert parse("<div id=\"test\">") == [start_tag: {"div", [{"id", [text: "test"]}]}]
    end

    test "expression" do
      assert parse("<div id={1 + 2}>") == [
               start_tag: {"div", [{"id", [expression: "{1 + 2}"]}]}
             ]
    end

    test "expression in double quotes" do
      assert parse("<div id=\"{1 + 2}\">") == [
               start_tag: {"div", [{"id", [text: "", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "text, expression" do
      assert parse("<div id=\"abc{1 + 2}\">") == [
               start_tag: {"div", [{"id", [text: "abc", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "expression, text" do
      assert parse("<div id=\"{1 + 2}abc\">") == [
               start_tag: {"div", [{"id", [text: "", expression: "{1 + 2}", text: "abc"]}]}
             ]
    end

    test "text, expression, text" do
      assert parse("<div id=\"abc{1 + 2}xyz\">") == [
               start_tag: {"div", [{"id", [text: "abc", expression: "{1 + 2}", text: "xyz"]}]}
             ]
    end

    test "boolean attribute followed by whitespace" do
      assert parse("<div my_attr >") == [start_tag: {"div", [{"my_attr", []}]}]
    end

    test "boolean attribute followed by start tag closing" do
      assert parse("<div my_attr>") == [start_tag: {"div", [{"my_attr", []}]}]
    end

    test "multiple attributes" do
      assert parse(~s(<div attr_1="value_1" attr_2="value_2">)) == [
               start_tag: {"div", [{"attr_1", [text: "value_1"]}, {"attr_2", [text: "value_2"]}]}
             ]
    end
  end

  describe "property" do
    test "text" do
      assert parse("<Aaa.Bbb id=\"test\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "test"]}]}
             ]
    end

    test "expression" do
      assert parse("<Aaa.Bbb id={1 + 2}>") == [
               start_tag: {"Aaa.Bbb", [{"id", [expression: "{1 + 2}"]}]}
             ]
    end

    test "expression in double quotes" do
      assert parse("<Aaa.Bbb id=\"{1 + 2}\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "text, expression" do
      assert parse("<Aaa.Bbb id=\"abc{1 + 2}\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "abc", expression: "{1 + 2}", text: ""]}]}
             ]
    end

    test "expression, text" do
      assert parse("<Aaa.Bbb id=\"{1 + 2}abc\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "", expression: "{1 + 2}", text: "abc"]}]}
             ]
    end

    test "text, expression, text" do
      assert parse("<Aaa.Bbb id=\"abc{1 + 2}xyz\">") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "abc", expression: "{1 + 2}", text: "xyz"]}]}
             ]
    end

    test "boolean property followed by whitespace" do
      assert parse("<Aaa.Bbb my_prop >") == [start_tag: {"Aaa.Bbb", [{"my_prop", []}]}]
    end

    test "boolean property followed by start tag closing" do
      assert parse("<Aaa.Bbb my_prop>") == [start_tag: {"Aaa.Bbb", [{"my_prop", []}]}]
    end

    test "multiple properties" do
      assert parse(~s(<Aaa.Bbb prop_1="value_1" prop_2="value_2">)) == [
               start_tag:
                 {"Aaa.Bbb", [{"prop_1", [text: "value_1"]}, {"prop_2", [text: "value_2"]}]}
             ]
    end
  end

  describe "expression" do
    test "empty" do
      assert parse("{}") == [expression: "{}"]
    end

    test "whitespaces" do
      assert parse("{ \n\r\t}") == [expression: "{ \n\r\t}"]
    end

    test "string, ASCI alphabet lowercase" do
      markup = "{abcdefghijklmnopqrstuvwxyz}"
      assert parse(markup) == [expression: markup]
    end

    test "string, ASCI alphabet uppercase" do
      markup = "{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"
      assert parse(markup) == [expression: markup]
    end

    test "string, UTF-8 chars" do
      markup = "{ąćęłńóśźżĄĆĘŁŃÓŚŹŻ}"
      assert parse(markup) == [expression: markup]
    end

    test "symbols" do
      markup = "{!@#$%^&*()-_=+[];:\\\'\\\"\\|,./?`~}"
      assert parse(markup) == [expression: markup]
    end

    test "single group of curly brackets" do
      markup = "{{123}}"
      assert parse(markup) == [expression: markup]
    end

    test "multiple groups of curly brackets" do
      markup = "{{1},{2}}"
      assert parse(markup) == [expression: markup]
    end

    test "opening curly bracket escaping inside double quotes" do
      markup = "{{\"\\{123\"}}"
      assert parse(markup) == [expression: markup]
    end

    test "opening curly bracket escaping inside single quotes" do
      markup = "{{'\\{123'}}"
      assert parse(markup) == [expression: markup]
    end

    test "closing curly bracket escaping inside double quotes" do
      markup = "{{\"123\\}\"}}"
      assert parse(markup) == [expression: markup]
    end

    test "closing curly bracket escaping inside single quotes" do
      markup = "{{'123\\}'}}"
      assert parse(markup) == [expression: markup]
    end

    test "single group of double quotes" do
      markup = "{{\"123\"}}"
      assert parse(markup) == [expression: markup]
    end

    test "multiple groups of double quotes" do
      markup = "{{\"1\",\"2\"}}"
      assert parse(markup) == [expression: markup]
    end

    test "single group of single quotes" do
      markup = "{{'123'}}"
      assert parse(markup) == [expression: markup]
    end

    test "multiple groups of single quotes" do
      markup = "{{'1','2'}}"
      assert parse(markup) == [expression: markup]
    end

    test "single quote nested in double quotes" do
      markup = "{\"abc'xyz\"}"
      assert parse(markup) == [expression: markup]
    end

    test "double quote nested in single quotes" do
      markup = "{'abc\"xyz'}"
      assert parse(markup) == [expression: markup]
    end

    test "double quote escaping" do
      markup = "{{1\\\"2}}"
      assert parse(markup) == [expression: markup]
    end

    test "single quote escaping" do
      markup = "{{1\\\'2}}"
      assert parse(markup) == [expression: markup]
    end

    test "opening curly bracket inside double quotes" do
      markup = "{{\"1\\{2\"}}"
      assert parse(markup) == [expression: markup]
    end

    test "opening curly bracket inside single quotes" do
      markup = "{{'1\\{2'}}"
      assert parse(markup) == [expression: markup]
    end

    test "closing curly bracket inside double quotes" do
      markup = "{{\"1\\}2\"}}"
      assert parse(markup) == [expression: markup]
    end

    test "closing curly bracket inside single quotes" do
      markup = "{{'1\\}2'}}"
      assert parse(markup) == [expression: markup]
    end

    test "non-nested elixir interpolation inside double quotes" do
      markup = "{\"aaa\#{123}bbb\"}"
      assert parse(markup) == [expression: "{\"aaa\#{123}bbb\"}"]
    end

    test "nested elixir interpolation inside double quotes" do
      markup = "{\"aaa\#{\"bbb\#{123}ccc\"}ddd\"}"
      assert parse(markup) == [expression: "{\"aaa\#{\"bbb\#{123}ccc\"}ddd\"}"]
    end

    test "non-nested elixir interpolation inside single quotes" do
      markup = "{'aaa\#{123}bbb'}"
      assert parse(markup) == [expression: "{'aaa\#{123}bbb'}"]
    end

    test "nested elixir interpolation inside single quotes" do
      markup = "{'aaa\#{'bbb\#{123}ccc'}ddd'}"
      assert parse(markup) == [expression: "{'aaa\#{'bbb\#{123}ccc'}ddd'}"]
    end

    test "nested elixir interpolation inside double and single quotes" do
      markup = "{\"aaa\#{'bbb\#{123}ccc'}ddd\"}"
      assert parse(markup) == [expression: "{\"aaa\#{'bbb\#{123}ccc'}ddd\"}"]
    end

    test "nested elixir interpolation inside single and double quotes" do
      markup = "{'aaa\#{\"bbb\#{123}ccc\"}ddd'}"
      assert parse(markup) == [expression: "{'aaa\#{\"bbb\#{123}ccc\"}ddd'}"]
    end

    test "inside text" do
      assert parse("abc{@kmn}xyz") == [text: "abc", expression: "{@kmn}", text: "xyz"]
    end

    test "inside element" do
      assert parse("<div>{@abc}</div>") == [
               start_tag: {"div", []},
               expression: "{@abc}",
               end_tag: "div"
             ]
    end

    test "inside component" do
      assert parse("<Aaa.Bbb>{@abc}</Aaa.Bbb>") == [
               start_tag: {"Aaa.Bbb", []},
               expression: "{@abc}",
               end_tag: "Aaa.Bbb"
             ]
    end
  end

  describe "block start" do
    test "without expression" do
      assert parse("{#abc}") == [block_start: {"abc", "{}"}]
    end

    test "with whitespace expression" do
      assert parse("{#abc \n\r\t}") == [block_start: {"abc", "{ \n\r\t}"}]
    end

    test "with non-whitespace expression" do
      assert parse("{#if abc == {1, 2}}") == [block_start: {"if", "{ abc == {1, 2}}"}]
    end

    test "inside text" do
      assert parse("abc{#kmn}xyz") == [text: "abc", block_start: {"kmn", "{}"}, text: "xyz"]
    end

    test "inside element" do
      assert parse("<div>{#abc}</div>") == [
               start_tag: {"div", []},
               block_start: {"abc", "{}"},
               end_tag: "div"
             ]
    end

    test "inside component" do
      assert parse("<Aaa.Bbb>{#abc}</Aaa.Bbb>") == [
               start_tag: {"Aaa.Bbb", []},
               block_start: {"abc", "{}"},
               end_tag: "Aaa.Bbb"
             ]
    end
  end

  describe "block end" do
    test "isolated" do
      assert parse("{/abc}") == [block_end: "abc"]
    end

    test "inside text" do
      assert parse("abc{/kmn}xyz") == [text: "abc", block_end: "kmn", text: "xyz"]
    end
  end

  describe "block" do
    test "single" do
      assert parse("{#abc}{/abc}") == [block_start: {"abc", "{}"}, block_end: "abc"]
    end

    test "multiple, siblings" do
      assert parse("{#abc}{/abc}{#xyz}{/xyz}") == [
               block_start: {"abc", "{}"},
               block_end: "abc",
               block_start: {"xyz", "{}"},
               block_end: "xyz"
             ]
    end

    test "multiple, nested" do
      assert parse("{#abc}{#xyz}{/xyz}{/abc}") == [
               block_start: {"abc", "{}"},
               block_start: {"xyz", "{}"},
               block_end: "xyz",
               block_end: "abc"
             ]
    end
  end

  describe "raw block" do
    test "block start" do
      assert parse("{#raw}") == []
    end

    test "block end" do
      assert parse("{#raw}{/raw}") == []
    end

    test "with text" do
      assert parse("{#raw}abc{/raw}") == [text: "abc"]
    end

    test "with element" do
      assert parse("{#raw}<div></div>{/raw}") == [start_tag: {"div", []}, end_tag: "div"]
    end

    test "with component" do
      assert parse("{#raw}<MyComponent></MyComponent>{/raw}") == [
               start_tag: {"MyComponent", []},
               end_tag: "MyComponent"
             ]
    end

    test "with expression" do
      assert parse("{#raw}{1 + 2}{/raw}") == [text: "{1 + 2}"]
    end

    test "with expression nested in text" do
      assert parse("{#raw}aaa{@test}bbb{/raw}") == [text: "aaa{@test}bbb"]
    end

    test "with template block" do
      assert parse("{#raw}{#abc}{/abc}{/raw}") == [text: "{#abc}{/abc}"]
    end

    test "with '=' char nested in text" do
      assert parse("{#raw}aaa = bbb{/raw}") == [text: "aaa = bbb"]
    end

    test "with '\"' char nested in text" do
      assert parse("{#raw}aaa \" bbb{/raw}") == [text: "aaa \" bbb"]
    end

    test "with \"'\" char nested in text" do
      assert parse("{#raw}aaa ' bbb{/raw}") == [text: "aaa ' bbb"]
    end

    test "with element having an attribute value with expression in double quotes" do
      assert parse("{#raw}<div id=\"aaa{@test}bbb\"></div>{/raw}") == [
               start_tag: {"div", [{"id", [text: "aaa{@test}bbb"]}]},
               end_tag: "div"
             ]
    end

    test "with component having a property value with expression in double quotes" do
      assert parse("{#raw}<Aaa.Bbb id=\"aaa{@test}bbb\"></Aaa.Bbb>{/raw}") == [
               start_tag: {"Aaa.Bbb", [{"id", [text: "aaa{@test}bbb"]}]},
               end_tag: "Aaa.Bbb"
             ]
    end

    test "inside text" do
      assert parse("abc{#raw}{/raw}xyz") == [text: "abcxyz"]
    end

    test "inside element" do
      assert parse("<div>{#raw}{/raw}</div>") == [start_tag: {"div", []}, end_tag: "div"]
    end

    test "inside component" do
      assert parse("<MyComponent>{#raw}{/raw}</MyComponent>") == [
               start_tag: {"MyComponent", []},
               end_tag: "MyComponent"
             ]
    end
  end

  describe "script" do
    test "single group of double quotes" do
      assert parse("<script>\"abc\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc\"",
               end_tag: "script"
             ]
    end

    test "multiple groups of double quotes" do
      assert parse(~s(<script>"abc" + "xyz"</script>)) == [
               start_tag: {"script", []},
               text: "\"abc\" + \"xyz\"",
               end_tag: "script"
             ]
    end

    test "single group of single quotes" do
      assert parse("<script>'abc'</script>") == [
               start_tag: {"script", []},
               text: "'abc'",
               end_tag: "script"
             ]
    end

    test "multiple groups of single quotes" do
      assert parse("<script>'abc' + 'xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc' + 'xyz'",
               end_tag: "script"
             ]
    end

    test "single group of backticks" do
      assert parse("<script>`abc`</script>") == [
               start_tag: {"script", []},
               text: "`abc`",
               end_tag: "script"
             ]
    end

    test "multiple groups of backticks" do
      assert parse("<script>`abc` + `xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc` + `xyz`",
               end_tag: "script"
             ]
    end

    test "symbol '<' not inside double or single quotes" do
      assert parse("<script>1 < 2</script>") == [
               start_tag: {"script", []},
               text: "1 < 2",
               end_tag: "script"
             ]
    end

    test "symbol '<' inside double quotes" do
      assert parse("<script>\"1 < 2\"</script>") == [
               start_tag: {"script", []},
               text: "\"1 < 2\"",
               end_tag: "script"
             ]
    end

    test "symbol '<' inside single quotes" do
      assert parse("<script>'1 < 2'</script>") == [
               start_tag: {"script", []},
               text: "'1 < 2'",
               end_tag: "script"
             ]
    end

    test "symbol '>' not inside double quotes" do
      assert parse("<script>1 > 2</script>") == [
               start_tag: {"script", []},
               text: "1 > 2",
               end_tag: "script"
             ]
    end

    test "symbol '>' inside double quotes" do
      assert parse("<script>\"1 > 2\"</script>") == [
               start_tag: {"script", []},
               text: "\"1 > 2\"",
               end_tag: "script"
             ]
    end

    test "symbol '>' inside single quotes" do
      assert parse("<script>'1 > 2'</script>") == [
               start_tag: {"script", []},
               text: "'1 > 2'",
               end_tag: "script"
             ]
    end

    test "symbol '</' inside double quotes" do
      assert parse("<script>\"abc</xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc</xyz\"",
               end_tag: "script"
             ]
    end

    test "symbol '</' inside single quotes" do
      assert parse("<script>'abc</xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc</xyz'",
               end_tag: "script"
             ]
    end

    test "expression" do
      assert parse("<script>const abc = {1 + 2};</script>") == [
               start_tag: {"script", []},
               text: "const abc = ",
               expression: "{1 + 2}",
               text: ";",
               end_tag: "script"
             ]
    end

    test "double quote nested in single quotes" do
      assert parse("<script>'abc\"xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc\"xyz'",
               end_tag: "script"
             ]
    end

    test "double quote nested in backticks" do
      assert parse("<script>`abc\"xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc\"xyz`",
               end_tag: "script"
             ]
    end

    test "single quote nested in double quotes" do
      assert parse("<script>\"abc'xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc'xyz\"",
               end_tag: "script"
             ]
    end

    test "single quote nested in backticks" do
      assert parse("<script>`abc'xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc'xyz`",
               end_tag: "script"
             ]
    end

    test "backtick nested in double quotes" do
      assert parse("<script>\"abc`xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc`xyz\"",
               end_tag: "script"
             ]
    end

    test "backtick nested in single quotes" do
      assert parse("<script>'abc`xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc`xyz'",
               end_tag: "script"
             ]
    end

    test "script end tag inside double quotes" do
      assert parse("<script>const abc = 'substr' + \"</script>\";</script>") == [
               start_tag: {"script", []},
               text: "const abc = 'substr' + \"</script>\";",
               end_tag: "script"
             ]
    end

    test "script end tag inside single quotes" do
      assert parse("<script>const abc = 'substr' + '</script>';</script>") == [
               start_tag: {"script", []},
               text: "const abc = 'substr' + '</script>';",
               end_tag: "script"
             ]
    end

    test "script end tag inside backticks" do
      assert parse("<script>const abc = 'substr' + `</script>`;</script>") == [
               start_tag: {"script", []},
               text: "const abc = 'substr' + `</script>`;",
               end_tag: "script"
             ]
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

      {#raw}<div id={@abc}></div>{/raw}
                    ^
      """

      test_syntax_error_msg("{#raw}<div id={@abc}></div>{/raw}", msg)
    end

    test "expression property value inside raw block" do
      msg = """
      Reason:
      Expression property value inside raw block detected.

      Hint:
      Either wrap the property value with double quotes or remove the parent raw block".

      {#raw}<Aa.Bb id={@abc}></Aa.Bb>{/raw}
                      ^
      """

      test_syntax_error_msg("{#raw}<Aa.Bb id={@abc}></Aa.Bb>{/raw}", msg)
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
