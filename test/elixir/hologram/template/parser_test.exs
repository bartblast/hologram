defmodule Hologram.Template.ParserTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Parser
  alias Hologram.TemplateSyntaxError

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

  defp test_syntax_error_msg(markup, expected_msg) do
    normalized_expected_msg = normalize_newlines(expected_msg)
    regex = ~r/#{Regex.escape(normalized_expected_msg)}/s

    assert_raise TemplateSyntaxError, regex, fn ->
      parse_markup(markup)
    end
  end

  test "parse_markup/1" do
    markup = "<div id=\"test\"></div>"

    assert parse_markup(markup) == [start_tag: {"div", [{"id", [text: "test"]}]}, end_tag: "div"]
  end

  describe "text" do
    test "empty" do
      assert parse_markup("") == []
    end

    test "with whitespaces" do
      markup = " \n\r\t"
      assert parse_markup(markup) == [text: markup]
    end

    test "with symbols" do
      markup = "#$%"
      assert parse_markup(markup) == [text: markup]
    end

    test "with string" do
      markup = "abc"
      assert parse_markup(markup) == [text: markup]
    end
  end

  describe "standard element tags" do
    test "non-void HTML element start tag" do
      assert parse_markup("<div>") == [start_tag: {"div", []}]
    end

    test "void HTML element, unclosed start tag" do
      assert parse_markup("<br>") == [self_closing_tag: {"br", []}]
    end

    test "void HTML element, self-closed start tag" do
      assert parse_markup("<br />") == [self_closing_tag: {"br", []}]
    end

    test "SVG element, unclosed start tag" do
      assert parse_markup("<path>") == [start_tag: {"path", []}]
    end

    test "SVG element, self-closed start tag" do
      assert parse_markup("<path />") == [self_closing_tag: {"path", []}]
    end

    test "slot element, unclosed start tag" do
      assert parse_markup("<slot>") == [self_closing_tag: {"slot", []}]
    end

    test "slot element, self-closed start tag" do
      assert parse_markup("<slot />") == [self_closing_tag: {"slot", []}]
    end

    test "whitespaces after unclosed start tag name" do
      assert parse_markup("<div \n\r\t>") == [start_tag: {"div", []}]
    end

    test "end tag" do
      assert parse_markup("</div>") == [end_tag: "div"]
    end

    test "whitespaces after end tag name" do
      assert parse_markup("</div \n\r\t>") == [end_tag: "div"]
    end
  end

  describe "custom element tags" do
    test "start tag with single hyphen" do
      assert parse_markup("<foo-bar>") == [start_tag: {"foo-bar", []}]
    end

    test "start tag with multiple hyphens" do
      assert parse_markup("<foo-bar-baz>") == [start_tag: {"foo-bar-baz", []}]
    end

    test "start tag with trailing hyphen" do
      assert parse_markup("<foo->") == [start_tag: {"foo-", []}]
    end

    test "start tag with consecutive hyphens" do
      assert parse_markup("<foo--bar>") == [start_tag: {"foo--bar", []}]
    end

    test "self-closed start tag with single hyphen" do
      assert parse_markup("<foo-bar />") == [self_closing_tag: {"foo-bar", []}]
    end

    test "self-closed start tag with multiple hyphens" do
      assert parse_markup("<foo-bar-baz />") == [self_closing_tag: {"foo-bar-baz", []}]
    end

    test "self-closed start tag with trailing hyphen" do
      assert parse_markup("<foo- />") == [self_closing_tag: {"foo-", []}]
    end

    test "self-closed start tag with consecutive hyphens" do
      assert parse_markup("<foo--bar />") == [self_closing_tag: {"foo--bar", []}]
    end

    test "end tag with single hyphen" do
      assert parse_markup("</foo-bar>") == [end_tag: "foo-bar"]
    end

    test "end tag with multiple hyphens" do
      assert parse_markup("</foo-bar-baz>") == [end_tag: "foo-bar-baz"]
    end

    test "end tag with trailing hyphen" do
      assert parse_markup("</foo->") == [end_tag: "foo-"]
    end

    test "end tag with consecutive hyphens" do
      assert parse_markup("</foo--bar>") == [end_tag: "foo--bar"]
    end

    test "start tag with attribute" do
      assert parse_markup(~s(<foo-bar class="x">)) == [
               start_tag: {"foo-bar", [{"class", [text: "x"]}]}
             ]
    end

    test "whitespaces after start tag name" do
      assert parse_markup("<foo-bar \n\r\t>") == [start_tag: {"foo-bar", []}]
    end

    test "round-trip with text content" do
      assert parse_markup("<foo-bar>text</foo-bar>") == [
               start_tag: {"foo-bar", []},
               text: "text",
               end_tag: "foo-bar"
             ]
    end

    test "leading hyphen in start tag raises error" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Tag names can't start with '-'.

        Hint:
        Tag names must start with a letter.

        <-foo>
         ^
        """)

      test_syntax_error_msg("<-foo>", expected_msg)
    end

    test "leading hyphen in end tag raises error" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Tag names can't start with '-'.

        Hint:
        Tag names must start with a letter.

        </-foo>
          ^
        """)

      test_syntax_error_msg("</-foo>", expected_msg)
    end

    test "raw text mode is not activated for script-prefixed custom element" do
      assert parse_markup("<script-widget>{@var}</script-widget>") == [
               start_tag: {"script-widget", []},
               expression: "{@var}",
               end_tag: "script-widget"
             ]
    end

    test "raw text mode is not activated for style-prefixed custom element" do
      assert parse_markup("<style-widget>{@var}</style-widget>") == [
               start_tag: {"style-widget", []},
               expression: "{@var}",
               end_tag: "style-widget"
             ]
    end

    test "raw text mode is still activated for script tag with attributes" do
      assert parse_markup(~s(<script defer>var x = "<div>";</script>)) == [
               start_tag: {"script", [{"defer", []}]},
               text: ~s(var x = "<div>";),
               end_tag: "script"
             ]
    end

    test "raw text mode is still activated for style tag with attributes" do
      assert parse_markup(~s(<style media="print">a > b</style>)) == [
               start_tag: {"style", [{"media", [text: "print"]}]},
               text: "a > b",
               end_tag: "style"
             ]
    end
  end

  describe "style element" do
    test "child combinator is text" do
      assert parse_markup("<style>a > b</style>") == [
               start_tag: {"style", []},
               text: "a > b",
               end_tag: "style"
             ]
    end

    test "less-than char is text" do
      assert parse_markup("<style>a < b</style>") == [
               start_tag: {"style", []},
               text: "a < b",
               end_tag: "style"
             ]
    end

    test "start tag is not recognized" do
      assert parse_markup("<style><div></style>") == [
               start_tag: {"style", []},
               text: "<div>",
               end_tag: "style"
             ]
    end

    test "comment opener is text" do
      assert parse_markup("<style><!-- a --></style>") == [
               start_tag: {"style", []},
               text: "<!-- a -->",
               end_tag: "style"
             ]
    end

    test "end tag is recognized" do
      assert parse_markup("<style>a</style>b") == [
               start_tag: {"style", []},
               text: "a",
               end_tag: "style",
               text: "b"
             ]
    end

    test "end tag is not recognized inside quoting" do
      assert parse_markup(~s(<style>content: "</div>"</style>)) == [
               start_tag: {"style", []},
               text: ~s(content: "</div>"),
               end_tag: "style"
             ]
    end

    test "expression is still interpolated" do
      assert parse_markup("<style>{@color}</style>") == [
               start_tag: {"style", []},
               expression: "{@color}",
               end_tag: "style"
             ]
    end

    test "escaped braces are text" do
      assert parse_markup("<style>a \\{ b \\}</style>") == [
               start_tag: {"style", []},
               text: "a { b }",
               end_tag: "style"
             ]
    end

    test "raw text mode is off after the end tag" do
      assert_raise TemplateSyntaxError, ~r/Unescaped '>' character inside text node/, fn ->
        parse_markup("<style>a</style>b > c")
      end
    end
  end

  describe "component tags" do
    test "unclosed start tag" do
      assert parse_markup("<Aaa.Bbb>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "self-closed start tag" do
      assert parse_markup("<Aaa.Bbb />") == [self_closing_tag: {"Aaa.Bbb", []}]
    end

    test "whitespaces after unclosed start tag name" do
      assert parse_markup("<Aaa.Bbb \n\r\t>") == [start_tag: {"Aaa.Bbb", []}]
    end

    test "end tag" do
      assert parse_markup("</Aaa.Bbb>") == [end_tag: "Aaa.Bbb"]
    end

    test "whitespaces after end tag name" do
      assert parse_markup("</Aaa.Bbb \n\r\t>") == [end_tag: "Aaa.Bbb"]
    end
  end

  describe "dynamic tags" do
    test "start tag" do
      assert parse_markup("<{@module}>") == [start_tag: {{:expression, "{@module}"}, []}]
    end

    test "self-closed start tag" do
      assert parse_markup("<{@module} />") == [self_closing_tag: {{:expression, "{@module}"}, []}]
    end

    test "self-closing marker directly after tag expression" do
      assert parse_markup("<{@module}/>") == [self_closing_tag: {{:expression, "{@module}"}, []}]
    end

    test "whitespaces after tag expression" do
      assert parse_markup("<{@module} \n\r\t>") == [start_tag: {{:expression, "{@module}"}, []}]
    end

    test "void element name in expression doesn't self-close the tag" do
      assert parse_markup(~s(<{"br"}>)) == [start_tag: {{:expression, ~s({"br"})}, []}]
    end

    test "empty expression" do
      assert parse_markup("<{}>") == [start_tag: {{:expression, "{}"}, []}]
    end

    test "whitespaces in expression" do
      assert parse_markup("<{ \n\r\t@module \n\r\t}>") == [
               start_tag: {{:expression, "{ \n\r\t@module \n\r\t}"}, []}
             ]
    end

    test "module alias in expression" do
      assert parse_markup("<{Aaa.Bbb}>") == [start_tag: {{:expression, "{Aaa.Bbb}"}, []}]
    end

    test "string in expression" do
      assert parse_markup(~s(<{"my-widget"}>)) == [
               start_tag: {{:expression, ~s({"my-widget"})}, []}
             ]
    end

    test "function call in expression" do
      assert parse_markup("<{Map.fetch!(@modules, :my_key)}>") == [
               start_tag: {{:expression, "{Map.fetch!(@modules, :my_key)}"}, []}
             ]
    end

    test "nested curly brackets in expression" do
      assert parse_markup("<{%{my_key: %{my_nested_key: @module}}}>") == [
               start_tag: {{:expression, "{%{my_key: %{my_nested_key: @module}}}"}, []}
             ]
    end

    test "curly brackets inside double quotes in expression" do
      assert parse_markup(~s(<{@modules["{}"]}>)) == [
               start_tag: {{:expression, ~s({@modules["{}"]})}, []}
             ]
    end

    test "single quotes in expression" do
      assert parse_markup("<{@modules['my_key']}>") == [
               start_tag: {{:expression, "{@modules['my_key']}"}, []}
             ]
    end

    test "elixir interpolation in expression" do
      assert parse_markup("<{\"aaa\#{@tag}bbb\"}>") == [
               start_tag: {{:expression, "{\"aaa\#{@tag}bbb\"}"}, []}
             ]
    end

    test "angle brackets in expression" do
      assert parse_markup(~s(<{if @a < @b, do: "div", else: "span"}>)) == [
               start_tag: {{:expression, ~s({if @a < @b, do: "div", else: "span"})}, []}
             ]
    end

    test "attribute with text value" do
      assert parse_markup(~s(<{@module} my_key="my_value">)) == [
               start_tag: {{:expression, "{@module}"}, [{"my_key", [text: "my_value"]}]}
             ]
    end

    test "attribute with expression value" do
      assert parse_markup("<{@module} my_key={@my_value}>") == [
               start_tag: {{:expression, "{@module}"}, [{"my_key", [expression: "{@my_value}"]}]}
             ]
    end

    test "boolean attribute" do
      assert parse_markup("<{@module} my_key>") == [
               start_tag: {{:expression, "{@module}"}, [{"my_key", []}]}
             ]
    end

    test "event attribute" do
      assert parse_markup(~s(<{@module} $click="my_action">)) == [
               start_tag: {{:expression, "{@module}"}, [{"$click", [text: "my_action"]}]}
             ]
    end

    test "multiple attributes" do
      assert parse_markup(~s(<{@module} my_key_1="my_value_1" my_key_2={@my_value_2} />)) == [
               self_closing_tag:
                 {{:expression, "{@module}"},
                  [
                    {"my_key_1", [text: "my_value_1"]},
                    {"my_key_2", [expression: "{@my_value_2}"]}
                  ]}
             ]
    end

    test "spread" do
      assert parse_markup("<{@module} ...{@spread}>") == [
               start_tag: {{:expression, "{@module}"}, [spread: "{@spread}"]}
             ]
    end

    test "spread interleaved with named attributes, preserving order" do
      assert parse_markup(~s(<{@module} my_key_1="my_value_1" ...{@spread} my_key_2>)) == [
               start_tag:
                 {{:expression, "{@module}"},
                  [{"my_key_1", [text: "my_value_1"]}, {:spread, "{@spread}"}, {"my_key_2", []}]}
             ]
    end

    test "attributes are not carried over from the preceding tag" do
      assert parse_markup(~s(<div my_key="my_value"><{@module}>)) == [
               start_tag: {"div", [{"my_key", [text: "my_value"]}]},
               start_tag: {{:expression, "{@module}"}, []}
             ]
    end

    test "nested in element" do
      assert parse_markup("<div><{@module} /></div>") == [
               start_tag: {"div", []},
               self_closing_tag: {{:expression, "{@module}"}, []},
               end_tag: "div"
             ]
    end

    test "with nested element" do
      assert parse_markup("<{@module}><span>abc</span>") == [
               start_tag: {{:expression, "{@module}"}, []},
               start_tag: {"span", []},
               text: "abc",
               end_tag: "span"
             ]
    end

    test "after text" do
      assert parse_markup("abc<{@module} />") == [
               text: "abc",
               self_closing_tag: {{:expression, "{@module}"}, []}
             ]
    end

    test "inside if block" do
      assert parse_markup("{%if @flag}<{@module} />{/if}") == [
               block_start: {"if", "{ @flag}"},
               self_closing_tag: {{:expression, "{@module}"}, []},
               block_end: "if"
             ]
    end

    test "inside for block" do
      assert parse_markup("{%for module <- @modules}<{module} />{/for}") == [
               block_start: {"for", "{ module <- @modules}"},
               self_closing_tag: {{:expression, "{module}"}, []},
               block_end: "for"
             ]
    end

    test "start tag not recognized inside script" do
      assert parse_markup("<script><{@module}</script>") == [
               start_tag: {"script", []},
               text: "<",
               expression: "{@module}",
               end_tag: "script"
             ]
    end

    test "start tag not recognized inside public comment" do
      assert parse_markup("<!--<{@module}-->") == [
               :public_comment_start,
               {:text, "<"},
               {:expression, "{@module}"},
               :public_comment_end
             ]
    end

    test "end tag" do
      assert parse_markup("</{@module}>") == [end_tag: {:expression, "{@module}"}]
    end

    test "whitespaces after end tag expression" do
      assert parse_markup("</{@module} \n\r\t>") == [end_tag: {:expression, "{@module}"}]
    end

    test "whitespaces in end tag expression" do
      assert parse_markup("</{ \n\r\t@module \n\r\t}>") == [
               end_tag: {:expression, "{ \n\r\t@module \n\r\t}"}
             ]
    end

    test "nested curly brackets in end tag expression" do
      assert parse_markup("</{%{my_key: %{my_nested_key: @module}}}>") == [
               end_tag: {:expression, "{%{my_key: %{my_nested_key: @module}}}"}
             ]
    end

    test "curly brackets inside double quotes in end tag expression" do
      assert parse_markup(~s(</{@modules["{}"]}>)) == [
               end_tag: {:expression, ~s({@modules["{}"]})}
             ]
    end

    test "paired start and end tags" do
      assert parse_markup("<{@module}></{@module}>") == [
               start_tag: {{:expression, "{@module}"}, []},
               end_tag: {:expression, "{@module}"}
             ]
    end

    test "with text content" do
      assert parse_markup("<{@module}>abc</{@module}>") == [
               start_tag: {{:expression, "{@module}"}, []},
               text: "abc",
               end_tag: {:expression, "{@module}"}
             ]
    end

    test "with expression content" do
      assert parse_markup("<{@module}>{@content}</{@module}>") == [
               start_tag: {{:expression, "{@module}"}, []},
               expression: "{@content}",
               end_tag: {:expression, "{@module}"}
             ]
    end

    test "with element content" do
      assert parse_markup("<{@module}><span>abc</span></{@module}>") == [
               start_tag: {{:expression, "{@module}"}, []},
               start_tag: {"span", []},
               text: "abc",
               end_tag: "span",
               end_tag: {:expression, "{@module}"}
             ]
    end

    test "paired tags nested in element" do
      assert parse_markup("<div><{@module}>abc</{@module}></div>") == [
               start_tag: {"div", []},
               start_tag: {{:expression, "{@module}"}, []},
               text: "abc",
               end_tag: {:expression, "{@module}"},
               end_tag: "div"
             ]
    end

    test "nested paired tags" do
      assert parse_markup(
               "<{@outer_module}><{@inner_module}></{@inner_module}></{@outer_module}>"
             ) ==
               [
                 start_tag: {{:expression, "{@outer_module}"}, []},
                 start_tag: {{:expression, "{@inner_module}"}, []},
                 end_tag: {:expression, "{@inner_module}"},
                 end_tag: {:expression, "{@outer_module}"}
               ]
    end

    test "paired tags inside if block" do
      assert parse_markup("{%if @flag}<{@module}>abc</{@module}>{/if}") == [
               block_start: {"if", "{ @flag}"},
               start_tag: {{:expression, "{@module}"}, []},
               text: "abc",
               end_tag: {:expression, "{@module}"},
               block_end: "if"
             ]
    end

    test "paired tags inside for block" do
      assert parse_markup("{%for module <- @modules}<{module}>abc</{module}>{/for}") == [
               block_start: {"for", "{ module <- @modules}"},
               start_tag: {{:expression, "{module}"}, []},
               text: "abc",
               end_tag: {:expression, "{module}"},
               block_end: "for"
             ]
    end

    test "end tag recognized inside script, like static end tags are" do
      assert parse_markup("<script></{@module}></script>") == [
               start_tag: {"script", []},
               end_tag: {:expression, "{@module}"},
               end_tag: "script"
             ]
    end

    test "end tag not recognized inside script quoting" do
      assert parse_markup(~s(<script>"</{@module}>"</script>)) == [
               start_tag: {"script", []},
               text: ~s("</),
               expression: "{@module}",
               text: ~s(>"),
               end_tag: "script"
             ]
    end

    test "end tag not recognized inside public comment" do
      assert parse_markup("<!--</{@module}-->") == [
               :public_comment_start,
               {:text, "</"},
               {:expression, "{@module}"},
               :public_comment_end
             ]
    end
  end

  describe "expression" do
    test "empty" do
      assert parse_markup("{}") == [expression: "{}"]
    end

    test "with whitespaces" do
      markup = "{ \n\r\t}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "with symbols" do
      markup = "{#$%}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "with string" do
      markup = "{abc}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "with expression" do
      markup = "<!--{@abc}-->"

      assert parse_markup(markup) == [
               :public_comment_start,
               {:expression, "{@abc}"},
               :public_comment_end
             ]
    end
  end

  describe "attributes and properties" do
    Enum.each(
      [
        {"attribute", "div", "my_attr"},
        {"event handler", "div", "$click"},
        {"property", "Aaa.Bbb", "my_prop"}
      ],
      fn {name, tag, key} ->
        test "#{name} value text" do
          markup = "<#{unquote(tag)} #{unquote(key)}=\"test\">"

          assert parse_markup(markup) == [
                   start_tag: {unquote(tag), [{unquote(key), [text: "test"]}]}
                 ]
        end

        test "#{name} value expression" do
          markup = "<#{unquote(tag)} #{unquote(key)}={1 + 2}>"

          assert parse_markup(markup) == [
                   start_tag: {unquote(tag), [{unquote(key), [expression: "{1 + 2}"]}]}
                 ]
        end

        test "#{name} value expression in double quotes" do
          markup = "<#{unquote(tag)} #{unquote(key)}=\"{1 + 2}\">"

          assert parse_markup(markup) == [
                   start_tag:
                     {unquote(tag), [{unquote(key), [text: "", expression: "{1 + 2}", text: ""]}]}
                 ]
        end

        test "multi-part #{name} value: text, expression" do
          markup = "<#{unquote(tag)} #{unquote(key)}=\"abc{1 + 2}\">"

          assert parse_markup(markup) == [
                   start_tag:
                     {unquote(tag),
                      [{unquote(key), [text: "abc", expression: "{1 + 2}", text: ""]}]}
                 ]
        end

        test "multi-part #{name} value: expression, text" do
          markup = "<#{unquote(tag)} #{unquote(key)}=\"{1 + 2}abc\">"

          assert parse_markup(markup) == [
                   start_tag:
                     {unquote(tag),
                      [{unquote(key), [text: "", expression: "{1 + 2}", text: "abc"]}]}
                 ]
        end

        test "boolean #{name} followed by start tag closing" do
          markup = "<#{unquote(tag)} #{unquote(key)}>"
          assert parse_markup(markup) == [start_tag: {unquote(tag), [{unquote(key), []}]}]
        end

        test "multiple #{name}(s)" do
          markup = ~s(<#{unquote(tag)} #{unquote(key)}_1="value_1" #{unquote(key)}_2="value_2">)

          assert parse_markup(markup) == [
                   start_tag:
                     {unquote(tag),
                      [
                        {"#{unquote(key)}_1", [text: "value_1"]},
                        {"#{unquote(key)}_2", [text: "value_2"]}
                      ]}
                 ]
        end
      end
    )

    test "attribute with a dash char" do
      assert parse_markup(~s'<div aria-modal="true">') == [
               start_tag: {"div", [{"aria-modal", [text: "true"]}]}
             ]
    end

    test "event handler with a key filter" do
      assert parse_markup("<div $key_down.enter={:submit}>") == [
               start_tag: {"div", [{"$key_down.enter", [expression: "{:submit}"]}]}
             ]
    end

    test "event handler with a combined key filter" do
      assert parse_markup("<div $key_down.ctrl+k={:open_palette}>") == [
               start_tag: {"div", [{"$key_down.ctrl+k", [expression: "{:open_palette}"]}]}
             ]
    end

    # TODO: allow dash chars only in attributes
    # test "property with a dash char"
  end

  describe "spread" do
    Enum.each(
      [
        {"element", "div"},
        {"component", "Aaa.Bbb"}
      ],
      fn {name, tag} ->
        test "single spread in #{name} start tag" do
          markup = "<#{unquote(tag)} ...{@spread}>"

          assert parse_markup(markup) == [start_tag: {unquote(tag), [spread: "{@spread}"]}]
        end

        test "single spread in #{name} self-closing tag" do
          markup = "<#{unquote(tag)} ...{@spread} />"

          assert parse_markup(markup) == [self_closing_tag: {unquote(tag), [spread: "{@spread}"]}]
        end

        test "spread directly followed by #{name} self-closing tag end" do
          markup = "<#{unquote(tag)} ...{@spread}/>"

          assert parse_markup(markup) == [self_closing_tag: {unquote(tag), [spread: "{@spread}"]}]
        end

        test "multiple spreads in #{name} start tag" do
          markup = "<#{unquote(tag)} ...{@spread_1} ...{@spread_2}>"

          assert parse_markup(markup) == [
                   start_tag: {unquote(tag), [spread: "{@spread_1}", spread: "{@spread_2}"]}
                 ]
        end

        test "spread interleaved with named #{name} attributes, preserving order" do
          markup =
            ~s(<#{unquote(tag)} my_key_1="value_1" ...{@spread_1} my_key_2={@value_2} ...{@spread_2} my_key_3>)

          assert parse_markup(markup) == [
                   start_tag:
                     {unquote(tag),
                      [
                        {"my_key_1", [text: "value_1"]},
                        {:spread, "{@spread_1}"},
                        {"my_key_2", [expression: "{@value_2}"]},
                        {:spread, "{@spread_2}"},
                        {"my_key_3", []}
                      ]}
                 ]
        end

        test "spread directly after a quoted #{name} attribute value" do
          markup = ~s(<#{unquote(tag)} my_key="value"...{@spread}>)

          assert parse_markup(markup) == [
                   start_tag:
                     {unquote(tag), [{"my_key", [text: "value"]}, {:spread, "{@spread}"}]}
                 ]
        end
      end
    )

    test "void element start tag" do
      assert parse_markup("<br ...{@spread}>") == [
               self_closing_tag: {"br", [spread: "{@spread}"]}
             ]
    end

    test "empty expression" do
      assert parse_markup("<div ...{}>") == [start_tag: {"div", [spread: "{}"]}]
    end

    test "whitespaces in expression" do
      assert parse_markup("<div ...{ \n\r\t@spread \n\r\t}>") == [
               start_tag: {"div", [spread: "{ \n\r\t@spread \n\r\t}"]}
             ]
    end

    test "function call in expression" do
      assert parse_markup("<div ...{Map.merge(@base, @extra)}>") == [
               start_tag: {"div", [spread: "{Map.merge(@base, @extra)}"]}
             ]
    end

    test "map in expression" do
      assert parse_markup("<div ...{%{my_key: @value}}>") == [
               start_tag: {"div", [spread: "{%{my_key: @value}}"]}
             ]
    end

    test "nested curly brackets in expression" do
      assert parse_markup("<div ...{%{my_key: %{my_nested_key: @value}}}>") == [
               start_tag: {"div", [spread: "{%{my_key: %{my_nested_key: @value}}}"]}
             ]
    end

    test "bare keyword list shorthand in expression" do
      assert parse_markup(~s(<div ...{my_key_1: [my_key_2: "abc"], my_key_3: "xyz"}>)) == [
               start_tag: {"div", [spread: ~s({my_key_1: [my_key_2: "abc"], my_key_3: "xyz"})]}
             ]
    end

    test "double quotes in expression" do
      assert parse_markup(~s(<div ...{%{my_key: "abc"}}>)) == [
               start_tag: {"div", [spread: ~s({%{my_key: "abc"}})]}
             ]
    end

    test "curly brackets inside double quotes in expression" do
      assert parse_markup(~s(<div ...{%{my_key: "{}"}}>)) == [
               start_tag: {"div", [spread: ~s({%{my_key: "{}"}})]}
             ]
    end

    test "single quotes in expression" do
      assert parse_markup("<div ...{%{my_key: 'abc'}}>") == [
               start_tag: {"div", [spread: "{%{my_key: 'abc'}}"]}
             ]
    end

    test "curly brackets inside single quotes in expression" do
      assert parse_markup("<div ...{%{my_key: '{}'}}>") == [
               start_tag: {"div", [spread: "{%{my_key: '{}'}}"]}
             ]
    end

    test "elixir interpolation in expression" do
      assert parse_markup("<div ...{%{my_key: \"aaa\#{@value}bbb\"}}>") == [
               start_tag: {"div", [spread: "{%{my_key: \"aaa\#{@value}bbb\"}}"]}
             ]
    end

    test "angle brackets in expression" do
      assert parse_markup("<div ...{if @a < @b, do: @spread_1, else: @spread_2}>") == [
               start_tag: {"div", [spread: "{if @a < @b, do: @spread_1, else: @spread_2}"]}
             ]
    end

    test "inside if block" do
      assert parse_markup("{%if @flag}<div ...{@spread}></div>{/if}") == [
               block_start: {"if", "{ @flag}"},
               start_tag: {"div", [spread: "{@spread}"]},
               end_tag: "div",
               block_end: "if"
             ]
    end

    test "inside for block" do
      assert parse_markup("{%for item <- @items}<div ...{item}></div>{/for}") == [
               block_start: {"for", "{ item <- @items}"},
               start_tag: {"div", [spread: "{item}"]},
               end_tag: "div",
               block_end: "for"
             ]
    end

    test "expression containing a for block end marker" do
      assert parse_markup(~s(<div ...{%{my_key: "{/for}"}}>)) == [
               start_tag: {"div", [spread: ~s({%{my_key: "{/for}"}})]}
             ]
    end

    test "'...' marker not followed by '{' is parsed as an attribute name" do
      assert parse_markup("<div ...>") == [start_tag: {"div", [{"...", []}]}]
    end

    test "'...' marker separated from '{' by whitespace is not a spread" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unexpected '{' character.
        """)

      test_syntax_error_msg("<div ... {@spread}>", expected_msg)
    end

    test "text node expression is not affected" do
      assert parse_markup("<div>...{@spread}</div>") == [
               start_tag: {"div", []},
               text: "...",
               expression: "{@spread}",
               end_tag: "div"
             ]
    end
  end

  describe "public comment" do
    test "with text" do
      assert parse_markup("<!--abc-->") == [
               :public_comment_start,
               {:text, "abc"},
               :public_comment_end
             ]
    end

    test "with '<!--' symbol not followed by '>' symbol" do
      assert parse_markup("<!--<!--abc-->") == [
               :public_comment_start,
               {:text, "<!--abc"},
               :public_comment_end
             ]
    end

    test "with '<!--' symbol followed by '>' symbol" do
      assert parse_markup("<!--<!-->") == [
               :public_comment_start,
               {:text, "<!"},
               :public_comment_end
             ]
    end

    test "with DOCTYPE" do
      assert parse_markup("<!--<!DOCTYPE html>-->") == [
               :public_comment_start,
               {:text, "<!DOCTYPE html>"},
               :public_comment_end
             ]
    end

    test "with '<!' symbol" do
      assert parse_markup("<!--<!abc-->") == [
               :public_comment_start,
               {:text, "<!abc"},
               :public_comment_end
             ]
    end

    test "with '</' symbol" do
      assert parse_markup("<!--</-->") == [
               :public_comment_start,
               {:text, "</"},
               :public_comment_end
             ]
    end

    test "with '<' symbol" do
      assert parse_markup("<!--<-->") == [
               :public_comment_start,
               {:text, "<"},
               :public_comment_end
             ]
    end

    test "with '>' symbol" do
      assert parse_markup("<!-->-->") == [
               :public_comment_start,
               {:text, ">"},
               :public_comment_end
             ]
    end
  end

  test "DOCTYPE" do
    assert parse_markup("<!DoCtYpE html test_1 test_2 >") == [{:doctype, "html test_1 test_2"}]
  end

  describe "for block" do
    test "start" do
      assert parse_markup("{%for item <- @items}") == [
               block_start: {"for", "{ item <- @items}"}
             ]
    end

    test "end" do
      assert parse_markup("{/for}") == [block_end: "for"]
    end
  end

  describe "if block" do
    test "start" do
      assert parse_markup("{%if true}") == [block_start: {"if", "{ true}"}]
    end

    test "else subblock" do
      assert parse_markup("{%else}") == [block_start: "else"]
    end

    test "end" do
      assert parse_markup("{/if}") == [block_end: "if"]
    end
  end

  describe "raw block" do
    test "empty" do
      assert parse_markup("{%raw}{/raw}") == [block_start: "raw", block_end: "raw"]
    end

    test "literal raw text" do
      assert parse_markup("{%raw}raw{/raw}") == [
               block_start: "raw",
               text: "raw",
               block_end: "raw"
             ]
    end

    test "with whitespaces" do
      markup = " \n\r\t"

      assert parse_markup("{%raw}#{markup}{/raw}") == [
               block_start: "raw",
               text: markup,
               block_end: "raw"
             ]
    end

    test "with symbols" do
      markup = "#$%"

      assert parse_markup("{%raw}#{markup}{/raw}") == [
               block_start: "raw",
               text: markup,
               block_end: "raw"
             ]
    end

    test "with string" do
      markup = "abc"

      assert parse_markup("{%raw}#{markup}{/raw}") == [
               block_start: "raw",
               text: markup,
               block_end: "raw"
             ]
    end

    test "with element having an attribute value with expression in double quotes" do
      assert parse_markup("{%raw}<div id=\"aaa{@test}bbb\"></div>{/raw}") ==
               [
                 block_start: "raw",
                 start_tag: {"div", [{"id", [text: "aaa{@test}bbb"]}]},
                 end_tag: "div",
                 block_end: "raw"
               ]
    end

    test "with component having a property value with expression in double quotes" do
      assert parse_markup("{%raw}<Aaa.Bbb cid=\"aaa{@test}bbb\"></Aaa.Bbb>{/raw}") ==
               [
                 block_start: "raw",
                 start_tag: {"Aaa.Bbb", [{"cid", [text: "aaa{@test}bbb"]}]},
                 end_tag: "Aaa.Bbb",
                 block_end: "raw"
               ]
    end

    test "with script, having expression" do
      assert parse_markup("{%raw}<script>{@abc}</script>{/raw}") ==
               [
                 block_start: "raw",
                 start_tag: {"script", []},
                 text: "{@abc}",
                 end_tag: "script",
                 block_end: "raw"
               ]
    end

    test "with script, having javascript interpolation" do
      assert parse_markup("{%raw}<script>`abc${123}xyz`</script>{/raw}") ==
               [
                 block_start: "raw",
                 start_tag: {"script", []},
                 text: "`abc${123}xyz`",
                 end_tag: "script",
                 block_end: "raw"
               ]
    end

    test "within script" do
      assert parse_markup("<script>{%raw}{@abc}{/raw}</script>") == [
               start_tag: {"script", []},
               block_start: "raw",
               text: "{@abc}",
               block_end: "raw",
               end_tag: "script"
             ]
    end
  end

  describe "raw block with nested tag not using curly bracket" do
    tags = [
      {"text", "abc", block_start: "raw", text: "abc", block_end: "raw"},
      {"element start tag", "<div>",
       block_start: "raw", start_tag: {"div", []}, block_end: "raw"},
      {"element end tag", "</div>", block_start: "raw", end_tag: "div", block_end: "raw"},
      {"component start tag", "<Aaa.Bbb>",
       block_start: "raw", start_tag: {"Aaa.Bbb", []}, block_end: "raw"},
      {"component end tag", "</Aaa.Bbb>",
       block_start: "raw", end_tag: "Aaa.Bbb", block_end: "raw"},
      {"public comment", "<!--abc-->",
       [
         {:block_start, "raw"},
         :public_comment_start,
         {:text, "abc"},
         :public_comment_end,
         {:block_end, "raw"}
       ]},
      {"DOCTYPE", "<!DOCTYPE html>", block_start: "raw", doctype: "html", block_end: "raw"}
    ]

    Enum.each(tags, fn {name, markup, expected} ->
      test "raw block start, #{name}, raw block end" do
        markup = "{%raw}#{unquote(markup)}{/raw}"

        assert parse_markup(markup) == unquote(expected)
      end
    end)
  end

  describe "raw block with nested tag using curly brackets" do
    tags = [
      {"else subblock", "{%else}"},
      {"expression", "{@abc}"},
      {"for block start", "{%for item &lt;- @items}"},
      {"for block end", "{/for}"},
      {"if block start", "{%if true}"},
      {"if block end", "{/if}"}
    ]

    Enum.each(tags, fn {name, markup} ->
      test "raw block start, #{name}, raw block end" do
        markup = "{%raw}#{unquote(markup)}{/raw}"

        assert parse_markup(markup) == [
                 block_start: "raw",
                 text: unquote(markup),
                 block_end: "raw"
               ]
      end
    end)
  end

  describe "raw block nested in quotes" do
    test "inside double quotes within elixir expression" do
      markup = "{\"{%raw}{@abc}{/raw}\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "inside single quotes within elixir expression" do
      markup = "{'{%raw}{@abc}{/raw}'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "inside double quotes within javascript script" do
      assert parse_markup("<script>\"{%raw}{@abc}{/raw}\"</script>") == [
               start_tag: {"script", []},
               block_start: "raw",
               text: "\"{@abc}",
               block_end: "raw",
               text: "\"",
               end_tag: "script"
             ]
    end

    test "inside single quotes within javascript script" do
      assert parse_markup("<script>'{%raw}{@abc}{/raw}'</script>") == [
               start_tag: {"script", []},
               block_start: "raw",
               text: "'{@abc}",
               block_end: "raw",
               text: "'",
               end_tag: "script"
             ]
    end

    test "inside backtick quotes within javascript script" do
      assert parse_markup("<script>`{%raw}{@abc}{/raw}`</script>") == [
               start_tag: {"script", []},
               block_start: "raw",
               text: "`{@abc}",
               block_end: "raw",
               text: "`",
               end_tag: "script"
             ]
    end
  end

  describe "raw block after" do
    tags = [
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"},
      {"public comment", "<!--abc-->",
       [:public_comment_start, {:text, "abc"}, :public_comment_end]},
      {"DOCTYPE", "<!DOCTYPE html>", doctype: "html"},
      {"else subblock", "{%else}", block_start: "else"},
      {"expression", "{@abc}", expression: "{@abc}"},
      {"for block start", "{%for item <- @items}", block_start: {"for", "{ item <- @items}"}},
      {"for block end", "{/for}", block_end: "for"},
      {"if block start", "{%if true}", block_start: {"if", "{ true}"}},
      {"if block end", "{/if}", block_end: "if"}
    ]

    Enum.each(tags, fn {name, markup, expected} ->
      test "#{name}" do
        markup = "#{unquote(markup)}{%raw}{@abc}{/raw}"

        # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
        assert parse_markup(markup) ==
                 unquote(expected) ++ [block_start: "raw", text: "{@abc}", block_end: "raw"]
      end
    end)

    test "text" do
      assert parse_markup("abc{%raw}{@abc}{/raw}") == [
               block_start: "raw",
               text: "abc{@abc}",
               block_end: "raw"
             ]
    end
  end

  describe "tag combinations other than raw block" do
    tags = [
      {"text", "abc", text: "abc"},
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"},
      {"public comment", "<!--abc-->",
       [:public_comment_start, {:text, "abc"}, :public_comment_end]},
      {"DOCTYPE", "<!DOCTYPE html>", doctype: "html"},
      {"else subblock", "{%else}", block_start: "else"},
      {"expression", "{@abc}", expression: "{@abc}"},
      {"for block start", "{%for item <- @items}", block_start: {"for", "{ item <- @items}"}},
      {"for block end", "{/for}", block_end: "for"},
      {"if block start", "{%if true}", block_start: {"if", "{ true}"}},
      {"if block end", "{/if}", block_end: "if"}
    ]

    for(tag_1 <- tags, tag_2 <- tags, do: {tag_1, tag_2})
    |> Enum.reject(fn {{name_1, _markup_1, _expected_1}, {name_2, _markup_2, _expected_2}} ->
      name_1 == "text" && name_2 == "text"
    end)
    |> Enum.each(fn {{name_1, markup_1, expected_1}, {name_2, markup_2, expected_2}} ->
      test "#{name_1}, #{name_2}" do
        markup = "#{unquote(markup_1)}#{unquote(markup_2)}"
        assert parse_markup(markup) == unquote(expected_1) ++ unquote(expected_2)
      end
    end)
  end

  describe "special characters nested in various markup" do
    Enum.each(@special_chars, fn char ->
      test "'#{char}' character in text" do
        markup = "aaa#{unquote(char)}bbb"
        assert parse_markup(markup) == [text: markup]
      end

      test "'#{char}' character in public comment" do
        markup = "<!--#{unquote(char)}-->"

        assert parse_markup(markup) == [
                 :public_comment_start,
                 {:text, unquote(char)},
                 :public_comment_end
               ]
      end

      test "'#{char}' character in DOCTYPE" do
        markup = "<!DOCTYPE a#{unquote(char)}b >"
        assert parse_markup(markup) == [{:doctype, "a#{unquote(char)}b"}]
      end

      test "'#{char}' character in text interpolated expression" do
        markup = "{#{unquote(char)}}"
        assert parse_markup(markup) == [expression: markup]
      end

      test "'#{char}' character in attribute value text part" do
        markup = "<div my_attr=\"#{unquote(char)}\">"

        assert parse_markup(markup) == [
                 start_tag: {"div", [{"my_attr", [text: unquote(char)]}]}
               ]
      end

      test "'#{char}' character in attribute value expression part" do
        markup = "<div my_attr={#{unquote(char)}}>"

        assert parse_markup(markup) == [
                 start_tag: {"div", [{"my_attr", [expression: "{#{unquote(char)}}"]}]}
               ]
      end

      test "'#{char}' character in for block expression" do
        markup = "{%for #{unquote(char)}}{/for}"

        assert parse_markup(markup) == [
                 block_start: {"for", "{ #{unquote(char)}}"},
                 block_end: "for"
               ]
      end

      test "'#{char}' character in else subblock content" do
        markup = "{%else}#{unquote(char)}{/if}"

        assert parse_markup(markup) == [
                 block_start: "else",
                 text: "#{unquote(char)}",
                 block_end: "if"
               ]
      end

      test "'#{char}' character in for block content" do
        markup = "{%for item <- @items}#{unquote(char)}{/for}"

        assert parse_markup(markup) == [
                 block_start: {"for", "{ item <- @items}"},
                 text: "#{unquote(char)}",
                 block_end: "for"
               ]
      end

      test "'#{char}' character in if block expression" do
        markup = "{%if #{unquote(char)}}{/if}"

        assert parse_markup(markup) == [
                 block_start: {"if", "{ #{unquote(char)}}"},
                 block_end: "if"
               ]
      end

      test "'#{char}' character in if block content" do
        markup = "{%if true}#{unquote(char)}{/if}"

        assert parse_markup(markup) == [
                 block_start: {"if", "{ true}"},
                 text: "#{unquote(char)}",
                 block_end: "if"
               ]
      end

      test "'#{char}' character in raw block content" do
        markup = "{%raw}#{unquote(char)}{/raw}"

        assert parse_markup(markup) == [
                 block_start: "raw",
                 text: "#{unquote(char)}",
                 block_end: "raw"
               ]
      end

      test "'#{char}' character in script" do
        markup = "<script>#{unquote(char)}</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text: "#{unquote(char)}",
                 end_tag: "script"
               ]
      end
    end)
  end

  describe "special character preceding expression in text" do
    Enum.each(@special_chars, fn char ->
      test "'#{char}' character" do
        markup = "aaa #{unquote(char)}{@var} bbb"

        assert parse_markup(markup) == [
                 text: "aaa #{unquote(char)}",
                 expression: "{@var}",
                 text: " bbb"
               ]
      end
    end)
  end

  describe "tags nested in various markup" do
    tags = [
      {"element start tag", "<div>", start_tag: {"div", []}},
      {"element end tag", "</div>", end_tag: "div"},
      {"component start tag", "<Aaa.Bbb>", start_tag: {"Aaa.Bbb", []}},
      {"component end tag", "</Aaa.Bbb>", end_tag: "Aaa.Bbb"},
      {"public comment", "<!--abc-->",
       [:public_comment_start, {:text, "abc"}, :public_comment_end]},
      {"DOCTYPE", "<!DOCTYPE html>", doctype: "html"}
    ]

    Enum.each(tags, fn {name, markup, expected} ->
      test "#{name} inside text" do
        markup = "abc#{unquote(markup)}xyz"

        # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
        assert parse_markup(markup) == [{:text, "abc"}] ++ unquote(expected) ++ [{:text, "xyz"}]
      end

      test "#{name} inside else subblock" do
        markup = "{%else}#{unquote(markup)}{/if}"

        # credo:disable-for-lines:2 Credo.Check.Refactor.AppendSingleItem
        assert parse_markup(markup) ==
                 [{:block_start, "else"}] ++ unquote(expected) ++ [{:block_end, "if"}]
      end

      test "#{name} inside for block" do
        markup = "{%for item <- @items}#{unquote(markup)}{/for}"

        # credo:disable-for-lines:3 Credo.Check.Refactor.AppendSingleItem
        assert parse_markup(markup) ==
                 [{:block_start, {"for", "{ item <- @items}"}}] ++
                   unquote(expected) ++ [{:block_end, "for"}]
      end

      test "#{name} inside if block" do
        markup = "{%if true}#{unquote(markup)}{/if}"

        # credo:disable-for-lines:2 Credo.Check.Refactor.AppendSingleItem
        assert parse_markup(markup) ==
                 [{:block_start, {"if", "{ true}"}}] ++ unquote(expected) ++ [{:block_end, "if"}]
      end

      test "#{name} inside elixir expression double quoted string" do
        markup = "{\"#{unquote(markup)}\"}"
        assert parse_markup(markup) == [expression: markup]
      end

      test "#{name} inside elixir expression single quoted string" do
        markup = "{'#{unquote(markup)}'}"
        assert parse_markup(markup) == [expression: markup]
      end

      test "#{name} inside javascript script double quoted string" do
        markup = "<script>\"#{unquote(markup)}\"</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text: "\"#{unquote(markup)}\"",
                 end_tag: "script"
               ]
      end

      test "#{name} inside javascript script single quoted string" do
        markup = "<script>'#{unquote(markup)}'</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text: "'#{unquote(markup)}'",
                 end_tag: "script"
               ]
      end

      test "#{name} inside javascript script backtick quoted string" do
        markup = "<script>`#{unquote(markup)}`</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text: "`#{unquote(markup)}`",
                 end_tag: "script"
               ]
      end
    end)
  end

  describe "blocks in quoting inside expression" do
    quotings = [
      {"double quotes", "\""},
      {"single quotes", "'"}
    ]

    tags = [
      {"for", "item <- @items"},
      {"if", "true"}
    ]

    combinations = for quoting <- quotings, tag <- tags, do: {quoting, tag}

    Enum.each(combinations, fn {{quoting_name, char}, {tag_name, expr}} ->
      test "#{tag_name} block start in #{quoting_name}" do
        markup = "{#{unquote(char)}{%#{unquote(tag_name)} #{unquote(expr)}}#{unquote(char)}}"
        assert parse_markup(markup) == [expression: markup]
      end

      test "#{tag_name} block end in #{quoting_name}" do
        markup = "{#{unquote(char)}{/#{unquote(tag_name)}}#{unquote(char)}}"
        assert parse_markup(markup) == [expression: markup]
      end
    end)

    test "else subblock in double quotes" do
      markup = "{\"{%else}\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "else subblock in single quotes" do
      markup = "{'{%else}'}"
      assert parse_markup(markup) == [expression: markup]
    end
  end

  describe "blocks in quoting inside script" do
    quotings = [
      {"double quotes", "\""},
      {"single quotes", "'"},
      {"backtick quotes", "`"}
    ]

    tags = [
      {"for", "item <- @items"},
      {"if", "true"}
    ]

    combinations = for quoting <- quotings, tag <- tags, do: {quoting, tag}

    Enum.each(combinations, fn {{quoting_name, char}, {tag_name, expr}} ->
      test "#{tag_name} block start in #{quoting_name}" do
        markup =
          "<script>#{unquote(char)}{%#{unquote(tag_name)} #{unquote(expr)}}#{unquote(char)}</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text: unquote(char),
                 block_start: {unquote(tag_name), "{ #{unquote(expr)}}"},
                 text: unquote(char),
                 end_tag: "script"
               ]
      end

      test "#{tag_name} block end in #{quoting_name}" do
        markup = "<script>#{unquote(char)}{/#{unquote(tag_name)}}#{unquote(char)}</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text: unquote(char),
                 block_end: unquote(tag_name),
                 text: unquote(char),
                 end_tag: "script"
               ]
      end
    end)

    test "else subblock in double quotes" do
      markup = "<script>\"{%else}\"</script>"

      assert parse_markup(markup) == [
               start_tag: {"script", []},
               text: "\"",
               block_start: "else",
               text: "\"",
               end_tag: "script"
             ]
    end

    test "else subblock in single quotes" do
      markup = "<script>'{%else}'</script>"

      assert parse_markup(markup) == [
               start_tag: {"script", []},
               text: "'",
               block_start: "else",
               text: "'",
               end_tag: "script"
             ]
    end
  end

  describe "expression in quoting inside script" do
    test "in double quotes" do
      assert parse_markup("<script>\"abc{@my_var}xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc",
               expression: "{@my_var}",
               text: "xyz\"",
               end_tag: "script"
             ]
    end

    test "in single quotes" do
      assert parse_markup("<script>'abc{@my_var}xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc",
               expression: "{@my_var}",
               text: "xyz'",
               end_tag: "script"
             ]
    end

    test "in backtick quotes" do
      assert parse_markup("<script>`abc{@my_var}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc",
               expression: "{@my_var}",
               text: "xyz`",
               end_tag: "script"
             ]
    end

    test "inside javascript interpolation" do
      assert parse_markup("<script>`abc${123{@my_var}456}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${123",
               expression: "{@my_var}",
               text: "456}xyz`",
               end_tag: "script"
             ]
    end

    test "inside double quotes nested in javascription interpolation" do
      assert parse_markup("<script>`abc${\"123{@my_var}456\"}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${\"123",
               expression: "{@my_var}",
               text: "456\"}xyz`",
               end_tag: "script"
             ]
    end

    test "inside single quotes nested in javascription interpolation" do
      assert parse_markup("<script>`abc${'123{@my_var}456'}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${'123",
               expression: "{@my_var}",
               text: "456'}xyz`",
               end_tag: "script"
             ]
    end

    test "inside backtick quotes nested in javascription interpolation" do
      assert parse_markup("<script>`abc${`123{@my_var}456`}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${`123",
               expression: "{@my_var}",
               text: "456`}xyz`",
               end_tag: "script"
             ]
    end
  end

  describe "double quotes in expression" do
    test "escaping" do
      markup = "{\\\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "single group" do
      markup = "{\"123\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "multiple groups" do
      markup = "{\"1\", \"2\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "nested in single quotes" do
      markup = "{'abc\"xyz'}"
      assert parse_markup(markup) == [expression: markup]
    end
  end

  describe "double quotes in script" do
    test "escaping" do
      assert parse_markup("<script>\"abc\\\"xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc\\\"xyz\"",
               end_tag: "script"
             ]
    end

    test "single group" do
      assert parse_markup("<script>\"abc\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc\"",
               end_tag: "script"
             ]
    end

    test "multiple groups" do
      assert parse_markup(~s(<script>"abc" + "xyz"</script>)) == [
               start_tag: {"script", []},
               text: "\"abc\" + \"xyz\"",
               end_tag: "script"
             ]
    end

    test "nested in single quotes" do
      assert parse_markup("<script>'abc\"xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc\"xyz'",
               end_tag: "script"
             ]
    end

    test "nested in backticks" do
      assert parse_markup("<script>`abc\"xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc\"xyz`",
               end_tag: "script"
             ]
    end
  end

  describe "single quotes in expression" do
    test "escaping" do
      markup = "{\\'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "single group" do
      markup = "{'123'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "multiple groups" do
      markup = "{'1', '2'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "nested in double quotes" do
      markup = "{\"abc'xyz\"}"
      assert parse_markup(markup) == [expression: markup]
    end
  end

  describe "single quotes in script" do
    test "escaping" do
      assert parse_markup("<script>'abc\\'xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc\\'xyz'",
               end_tag: "script"
             ]
    end

    test "single group" do
      assert parse_markup("<script>'abc'</script>") == [
               start_tag: {"script", []},
               text: "'abc'",
               end_tag: "script"
             ]
    end

    test "multiple groups" do
      assert parse_markup("<script>'abc' + 'xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc' + 'xyz'",
               end_tag: "script"
             ]
    end

    test "nested in double quotes" do
      assert parse_markup("<script>\"abc'xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc'xyz\"",
               end_tag: "script"
             ]
    end

    test "nested in backticks" do
      assert parse_markup("<script>`abc'xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc'xyz`",
               end_tag: "script"
             ]
    end
  end

  describe "backtick quotes in script" do
    test "escaping" do
      assert parse_markup("<script>`abc\\`xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc\\`xyz`",
               end_tag: "script"
             ]
    end

    test "single group" do
      assert parse_markup("<script>`abc`</script>") == [
               start_tag: {"script", []},
               text: "`abc`",
               end_tag: "script"
             ]
    end

    test "multiple groups" do
      assert parse_markup("<script>`abc` + `xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc` + `xyz`",
               end_tag: "script"
             ]
    end

    test "nested in double quotes" do
      assert parse_markup("<script>\"abc`xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc`xyz\"",
               end_tag: "script"
             ]
    end

    test "nested in single quotes" do
      assert parse_markup("<script>'abc`xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc`xyz'",
               end_tag: "script"
             ]
    end
  end

  describe "curly brackets in expression" do
    test "single group in expression" do
      markup = "{{123}}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "multiple groups in expression" do
      markup = "{{1}, {2}}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "opening curly bracket inside double quotes in expression" do
      markup = "{\"{123\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "opening curly bracket inside single quotes in expression" do
      markup = "{'{123'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "closing curly bracket inside double quotes in expression" do
      markup = "{\"123}\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "closing curly bracket inside single quotes in expression" do
      markup = "{'123}'}"
      assert parse_markup(markup) == [expression: markup]
    end
  end

  describe "escaping curly brackets in text" do
    test "opening curly bracket" do
      assert parse_markup("abc\\{xyz") == [text: "abc{xyz"]
    end

    test "closing curly bracket" do
      assert parse_markup("abc\\}xyz") == [text: "abc}xyz"]
    end

    test "escaped curly brackets' processed tokens are accumulated in escaped form" do
      expected_msg =
        normalize_newlines("""
        aaa\\{bbb\\}ccc<div
                         ^\
        """)

      assert_raise TemplateSyntaxError, ~r/.+#{Regex.escape(expected_msg)}.+/s, fn ->
        parse_markup("aaa\\{bbb\\}ccc<div")
      end
    end
  end

  describe "angle brackets in script" do
    test "opening angle bracket '<' not inside quoting" do
      assert parse_markup("<script>1 < 2</script>") == [
               start_tag: {"script", []},
               text: "1 < 2",
               end_tag: "script"
             ]
    end

    test "closing angle bracket '>' not inside quoting" do
      assert parse_markup("<script>1 > 2</script>") == [
               start_tag: {"script", []},
               text: "1 > 2",
               end_tag: "script"
             ]
    end

    brackets = [
      {"opening angle bracket", "<"},
      {"closing angle bracket", ">"},
      {"opening bracket with slash", "</"},
      {"closing bracket with slash", "/>"}
    ]

    quotings = [
      {"double quotes", "\""},
      {"single quotes", "'"},
      {"backtick quotes", "`"}
    ]

    combinations = for bracket <- brackets, quoting <- quotings, do: {bracket, quoting}

    Enum.each(combinations, fn {{bracket_name, bracket_char}, {quoting_name, quoting_char}} ->
      test "#{bracket_name} '#{bracket_char}' inside #{quoting_name}" do
        markup =
          "<script>#{unquote(quoting_char)}1 #{unquote(bracket_char)} 2#{unquote(quoting_char)}</script>"

        assert parse_markup(markup) == [
                 start_tag: {"script", []},
                 text:
                   "#{unquote(quoting_char)}1 #{unquote(bracket_char)} 2#{unquote(quoting_char)}",
                 end_tag: "script"
               ]
      end
    end)
  end

  describe "elixir interpolation" do
    test "in text" do
      markup = "\#{@abc}"
      assert parse_markup(markup) == [text: "#", expression: "{@abc}"]
    end

    test "in public comment" do
      markup = "<!--\#{@abc}-->"

      assert parse_markup(markup) == [
               :public_comment_start,
               {:text, "#"},
               {:expression, "{@abc}"},
               :public_comment_end
             ]
    end

    test "in DOCTYPE" do
      markup = "<!DOCTYPE \#{@abc}>"
      assert parse_markup(markup) == [{:doctype, "\#{@abc}"}]
    end

    test "in expression, inside double quotes" do
      markup = "{\"aaa\#{123}bbb\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "in expression, inside single quotes" do
      markup = "{'aaa\#{123}bbb'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "in expression, nested inside double quotes and then inside double quotes" do
      markup = "{\"aaa\#{\"bbb\#{123}ccc\"}ddd\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "in expression, nested inside single quotes and then inside single quotes" do
      markup = "{'aaa\#{'bbb\#{123}ccc'}ddd'}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "in expression, nested inside double quotes and then inside single quotes" do
      markup = "{\"aaa\#{'bbb\#{123}ccc'}ddd\"}"
      assert parse_markup(markup) == [expression: markup]
    end

    test "in expression, nested inside single quotes and then inside double quotes" do
      markup = "{'aaa\#{\"bbb\#{123}ccc\"}ddd'}"
      assert parse_markup(markup) == [expression: markup]
    end

    # TODO: fix
    # test "in attribute value text part" do
    #   assert parse_markup("<div my_attr=\"\#{@abc}\">") == [
    #            start_tag: {"div", [{"my_attr", [text: "\#{@abc}"]}]}
    #          ]
    # end

    test "in attribute value expression part" do
      assert parse_markup("<div my_attr={\"\#{@abc}\"}>") == [
               start_tag: {"div", [{"my_attr", [expression: "{\"\#{@abc}\"}"]}]}
             ]
    end

    test "in for block expression" do
      assert parse_markup("{%for item <- [\"\#{@abc}\"]}{/for}") == [
               block_start: {"for", "{ item <- [\"\#{@abc}\"]}"},
               block_end: "for"
             ]
    end

    test "in if block expression" do
      assert parse_markup("{%if \"\#{@abc}\"}{/if}") == [
               block_start: {"if", "{ \"\#{@abc}\"}"},
               block_end: "if"
             ]
    end

    test "in raw block" do
      assert parse_markup("{%raw}\#{@abc}{/raw}") == [
               block_start: "raw",
               text: "\#{@abc}",
               block_end: "raw"
             ]
    end

    test "in script" do
      assert parse_markup("<script>\#{@abc}</script>") == [
               start_tag: {"script", []},
               text: "#",
               expression: "{@abc}",
               end_tag: "script"
             ]
    end
  end

  describe "script" do
    test "text" do
      assert parse_markup("<script>abc</script>") == [
               start_tag: {"script", []},
               text: "abc",
               end_tag: "script"
             ]
    end

    test "expression" do
      assert parse_markup("<script>{@abc}</script>") == [
               start_tag: {"script", []},
               expression: "{@abc}",
               end_tag: "script"
             ]
    end

    test "else subblock" do
      assert parse_markup("<script>{%else}</script>") == [
               start_tag: {"script", []},
               block_start: "else",
               end_tag: "script"
             ]
    end

    test "for block start" do
      assert parse_markup("<script>{%for item <- @items}</script>") == [
               start_tag: {"script", []},
               block_start: {"for", "{ item <- @items}"},
               end_tag: "script"
             ]
    end

    test "for block end" do
      assert parse_markup("<script>{/for}</script>") == [
               start_tag: {"script", []},
               block_end: "for",
               end_tag: "script"
             ]
    end

    test "if block start" do
      assert parse_markup("<script>{%if true}</script>") == [
               start_tag: {"script", []},
               block_start: {"if", "{ true}"},
               end_tag: "script"
             ]
    end

    test "if block end" do
      assert parse_markup("<script>{/if}</script>") == [
               start_tag: {"script", []},
               block_end: "if",
               end_tag: "script"
             ]
    end
  end

  describe "javascript interpolation" do
    test "in double quotes" do
      assert parse_markup("<script>\"abc${123}xyz\"</script>") == [
               start_tag: {"script", []},
               text: "\"abc${123}xyz\"",
               end_tag: "script"
             ]
    end

    test "in single quotes" do
      assert parse_markup("<script>'abc${123}xyz'</script>") == [
               start_tag: {"script", []},
               text: "'abc${123}xyz'",
               end_tag: "script"
             ]
    end

    test "in backtick quotes" do
      assert parse_markup("<script>`abc${123}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${123}xyz`",
               end_tag: "script"
             ]
    end

    test "nested double quotes" do
      assert parse_markup("<script>`abc${\"123\"}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${\"123\"}xyz`",
               end_tag: "script"
             ]
    end

    test "nested single quotes" do
      assert parse_markup("<script>`abc${'123'}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${'123'}xyz`",
               end_tag: "script"
             ]
    end

    test "nested backtick quotes" do
      assert parse_markup("<script>`abc${`123`}xyz`</script>") == [
               start_tag: {"script", []},
               text: "`abc${`123`}xyz`",
               end_tag: "script"
             ]
    end
  end

  describe "template syntax errors" do
    test "escape non-printable characters" do
      expected_msg = ~r/\na\\nb\\rc\\td < x\\ny\\rz\\tv\n {11}\^/s

      assert_raise TemplateSyntaxError, expected_msg, fn ->
        parse_markup("a\nb\rc\td < x\ny\rz\tv")
      end
    end

    test "strip excess characters" do
      expected_msg = ~r/\n2345678901234567890 < 1234567890123456789\n {20}\^/s

      assert_raise TemplateSyntaxError, expected_msg, fn ->
        parse_markup("123456789012345678901234567890 < 123456789012345678901234567890")
      end
    end

    test "unescaped '<' character inside text node" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unescaped '<' character inside text node.

        Hint:
        To escape use HTML entity: '&lt;'.

        abc < xyz
            ^
        """)

      test_syntax_error_msg("abc < xyz", expected_msg)
    end

    test "unescaped '>' character inside text node" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unescaped '>' character inside text node.

        Hint:
        To escape use HTML entity: '&gt;'.

        abc > xyz
            ^
        """)

      test_syntax_error_msg("abc > xyz", expected_msg)
    end

    test "expression attribute value inside raw block" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Expression attribute value inside raw block detected.

        Hint:
        Either wrap the attribute value with double quotes or remove the parent raw block".

        {%raw}<div id={@abc}></div>{/raw}
                      ^
        """)

      test_syntax_error_msg("{%raw}<div id={@abc}></div>{/raw}", expected_msg)
    end

    test "expression property value inside raw block" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Expression property value inside raw block detected.

        Hint:
        Either wrap the property value with double quotes or remove the parent raw block".

        {%raw}<Aa.Bb cid={@abc}></Aa.Bb>{/raw}
                         ^
        """)

      test_syntax_error_msg("{%raw}<Aa.Bb cid={@abc}></Aa.Bb>{/raw}", expected_msg)
    end

    test "unclosed start tag" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed start tag.

        Hint:
        Close the start tag with '>' character.

        <div
            ^
        """)

      test_syntax_error_msg("<div", expected_msg)
    end

    test "unclosed end tag" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed end tag.

        Hint:
        Close the end tag with '>' character.

        </div
             ^
        """)

      test_syntax_error_msg("</div", expected_msg)
    end

    test "unclosed end tag without a tag name" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed end tag.

        Hint:
        Close the end tag with '>' character.

        </
          ^
        """)

      test_syntax_error_msg("</", expected_msg)
    end

    test "unclosed dynamic end tag" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed end tag.

        Hint:
        Close the end tag with '>' character.

        </{@module}
                   ^
        """)

      test_syntax_error_msg("</{@module}", expected_msg)
    end

    test "unclosed public comment" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed public comment.

        Hint:
        Close the public comment with '-->' marker.

        <!--
            ^
        """)

      test_syntax_error_msg("<!--", expected_msg)
    end

    test "unclosed DOCTYPE declaration" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed DOCTYPE declaration.

        Hint:
        Close the DOCTYPE declaration with '>' character.

        <!DOCTYPE html
                      ^
        """)

      test_syntax_error_msg("<!DOCTYPE html", expected_msg)
    end

    test "'<!' symbol followed by a string other than 'DOCTYPE' (case insensitive)" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unescaped '<' character inside text node.

        Hint:
        To escape use HTML entity: '&lt;'.

        <!abc html>
        ^
        """)

      test_syntax_error_msg("<!abc html>", expected_msg)
    end

    test "'<!' symbol followed by a whitespace" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unescaped '<' character inside text node.

        Hint:
        To escape use HTML entity: '&lt;'.

        <! DOCTYPE html>
        ^
        """)

      test_syntax_error_msg("<! DOCTYPE html>", expected_msg)
    end

    test "missing attribute name" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Missing attribute name.

        Hint:
        Specify the attribute name before the '=' character.

        <div ="abc">
             ^
        """)

      test_syntax_error_msg("<div =\"abc\">", expected_msg)
    end

    test "expression in attribute position" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unexpected '{' character.

        Hint:
        To spread attributes or properties prefix the expression with the '...' marker, e.g. ...{@attrs}.

        <div {@spread}>
             ^
        """)

      test_syntax_error_msg("<div {@spread}>", expected_msg)
    end

    test "expression in property position" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unexpected '{' character.

        Hint:
        To spread attributes or properties prefix the expression with the '...' marker, e.g. ...{@attrs}.

        <Aa.Bb {@spread}>
               ^
        """)

      test_syntax_error_msg("<Aa.Bb {@spread}>", expected_msg)
    end

    test "expression in attribute position inside raw block" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unexpected '{' character inside raw block.

        Hint:
        Remove the parent raw block, then prefix the expression with the '...' marker to spread it, e.g. ...{@attrs}.

        {%raw}<div {@spread}></div>{/raw
                   ^
        """)

      test_syntax_error_msg("{%raw}<div {@spread}></div>{/raw}", expected_msg)
    end

    test "spread inside raw block" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Spread inside raw block detected.

        Hint:
        Remove the parent raw block to use the spread syntax.

        {%raw}<div ...{@spread}></div>{/ra
                   ^
        """)

      test_syntax_error_msg("{%raw}<div ...{@spread}></div>{/raw}", expected_msg)
    end

    test "unclosed spread expression" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed expression.

        Hint:
        Close the expression with '}' character.

        <div ...{@spread
                        ^
        """)

      test_syntax_error_msg("<div ...{@spread", expected_msg)
    end

    test "unclosed attribute value expression" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed expression.

        Hint:
        Close the expression with '}' character.

        iv my_key={@my_value
                            ^
        """)

      test_syntax_error_msg("<div my_key={@my_value", expected_msg)
    end

    test "unclosed expression in text" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed expression.

        Hint:
        Close the expression with '}' character.

        {@my_value
                  ^
        """)

      test_syntax_error_msg("{@my_value", expected_msg)
    end

    test "unclosed block start tag expression" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed expression.

        Hint:
        Close the expression with '}' character.

        {%if @my_condition
                          ^
        """)

      test_syntax_error_msg("{%if @my_condition", expected_msg)
    end

    test "dynamic end tag inside raw block" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Dynamic tag inside raw block detected.

        Hint:
        Remove the parent raw block to use the dynamic tag syntax.

        {%raw}</{@module}>{/raw}
              ^
        """)

      test_syntax_error_msg("{%raw}</{@module}>{/raw}", expected_msg)
    end

    test "unclosed dynamic end tag expression" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed expression.

        Hint:
        Close the expression with '}' character.

        </{@module
                  ^
        """)

      test_syntax_error_msg("</{@module", expected_msg)
    end

    test "dynamic start tag inside raw block" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Dynamic tag inside raw block detected.

        Hint:
        Remove the parent raw block to use the dynamic tag syntax.

        {%raw}<{@module}>{/raw}
              ^
        """)

      test_syntax_error_msg("{%raw}<{@module}>{/raw}", expected_msg)
    end

    test "unclosed dynamic start tag expression" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed expression.

        Hint:
        Close the expression with '}' character.

        <{@module
                 ^
        """)

      test_syntax_error_msg("<{@module", expected_msg)
    end

    test "unclosed dynamic start tag" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed start tag.

        Hint:
        Close the start tag with '>' character.

        <{@module}
                  ^
        """)

      test_syntax_error_msg("<{@module}", expected_msg)
    end

    test "unclosed start tag containing a spread" do
      expected_msg =
        normalize_newlines("""
        Reason:
        Unclosed start tag.

        Hint:
        Close the start tag with '>' character.

        <div ...{@spread}
                         ^
        """)

      test_syntax_error_msg("<div ...{@spread}", expected_msg)
    end
  end
end
