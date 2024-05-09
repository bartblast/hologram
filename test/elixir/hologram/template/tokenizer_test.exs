defmodule Hologram.Template.TokenizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Tokenizer

  test "empty" do
    assert tokenize("") == []
  end

  test "whitespaces" do
    assert tokenize(" \n\r\t") == [
             whitespace: " ",
             whitespace: "\n",
             whitespace: "\r",
             whitespace: "\t"
           ]
  end

  describe "quoting" do
    test "double quotes" do
      assert tokenize("\\\"\"") == [symbol: "\\\"", symbol: "\""]
    end

    test "single quotes" do
      assert tokenize("\\''") == [symbol: "\\'", symbol: "'"]
    end

    test "backticks" do
      assert tokenize("\\``") == [symbol: "\\`", symbol: "`"]
    end
  end

  describe "angle brackets" do
    test "opening" do
      assert tokenize("</.<!--.<./.<!.!.--.!--") == [
               symbol: "</",
               string: ".",
               symbol: "<!--",
               string: ".",
               symbol: "<",
               string: ".",
               symbol: "/",
               string: ".",
               symbol: "<!",
               string: ".!.",
               symbol: "-",
               symbol: "-",
               string: ".!",
               symbol: "-",
               symbol: "-"
             ]
    end

    test "closing" do
      assert tokenize("/>.-->.>./.--") == [
               symbol: "/>",
               string: ".",
               symbol: "-->",
               string: ".",
               symbol: ">",
               string: ".",
               symbol: "/",
               string: ".",
               symbol: "-",
               symbol: "-"
             ]
    end
  end

  describe "curly braces" do
    test "opening" do
      assert tokenize("\\{.{") == [symbol: "\\{", string: ".", symbol: "{"]
    end

    test "closing" do
      assert tokenize("\\}.}") == [symbol: "\\}", string: ".", symbol: "}"]
    end
  end

  describe "interpolation" do
    test "elixir" do
      assert tokenize("\\#.\#{.#.\\\#{.#\\{") == [
               symbol: "\\#",
               string: ".",
               symbol: "\#{",
               string: ".",
               symbol: "#",
               string: ".",
               symbol: "\\#",
               symbol: "{",
               string: ".",
               symbol: "#",
               symbol: "\\{"
             ]
    end

    test "javascript" do
      assert tokenize("\\$.${.$.\\${.$\\{") == [
               symbol: "\\$",
               string: ".",
               symbol: "${",
               string: ".",
               symbol: "$",
               string: ".",
               symbol: "\\$",
               symbol: "{",
               string: ".",
               symbol: "$",
               symbol: "\\{"
             ]
    end
  end

  describe "for block" do
    test "block start" do
      assert tokenize("{%for.\\{%for") == [
               symbol: "{%for",
               string: ".",
               symbol: "\\{",
               symbol: "%",
               string: "for"
             ]
    end

    test "block end" do
      assert tokenize("{/for}.\\{/for}.{/for\\}") == [
               symbol: "{/for}",
               string: ".",
               symbol: "\\{",
               symbol: "/",
               string: "for",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "/",
               string: "for",
               symbol: "\\}"
             ]
    end

    test "hash before block end" do
      assert tokenize("\#{/for}") == [{:symbol, "#"}, {:symbol, "{/for}"}]
    end

    test "dollar sign before block end" do
      assert tokenize("${/for}") == [{:symbol, "$"}, {:symbol, "{/for}"}]
    end
  end

  describe "if block" do
    test "block start" do
      assert tokenize("{%if.\\{%if") == [
               symbol: "{%if",
               string: ".",
               symbol: "\\{",
               symbol: "%",
               string: "if"
             ]
    end

    test "else subblock" do
      assert tokenize("{%else}.\\{%else}.{%else\\}") == [
               symbol: "{%else}",
               string: ".",
               symbol: "\\{",
               symbol: "%",
               string: "else",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "%",
               string: "else",
               symbol: "\\}"
             ]
    end

    test "block end" do
      assert tokenize("{/if}.\\{/if}.{/if\\}") == [
               symbol: "{/if}",
               string: ".",
               symbol: "\\{",
               symbol: "/",
               string: "if",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "/",
               string: "if",
               symbol: "\\}"
             ]
    end

    test "hash before block end" do
      assert tokenize("\#{/if}") == [{:symbol, "#"}, {:symbol, "{/if}"}]
    end

    test "dollar sign before block end" do
      assert tokenize("${/if}") == [{:symbol, "$"}, {:symbol, "{/if}"}]
    end
  end

  describe "raw block" do
    test "block start" do
      assert tokenize("{%raw}.\\{%raw}.{%raw\\}") == [
               symbol: "{%raw}",
               string: ".",
               symbol: "\\{",
               symbol: "%",
               string: "raw",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "%",
               string: "raw",
               symbol: "\\}"
             ]
    end

    test "block end" do
      assert tokenize("{/raw}.\\{/raw}.{/raw\\}") == [
               symbol: "{/raw}",
               string: ".",
               symbol: "\\{",
               symbol: "/",
               string: "raw",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "/",
               string: "raw",
               symbol: "\\}"
             ]
    end

    test "hash before block end" do
      assert tokenize("\#{/raw}") == [{:symbol, "#"}, {:symbol, "{/raw}"}]
    end

    test "dollar sign before block end" do
      assert tokenize("${/raw}") == [{:symbol, "$"}, {:symbol, "{/raw}"}]
    end
  end

  describe "other symbols" do
    test "backslash" do
      assert tokenize("\\") == [symbol: "\\"]
    end

    test "dollar sign" do
      assert tokenize("$") == [symbol: "$"]
    end

    test "equal sign" do
      assert tokenize("=") == [symbol: "="]
    end

    test "hyphen" do
      assert tokenize("-") == [symbol: "-"]
    end

    test "percentage sign" do
      assert tokenize("%") == [symbol: "%"]
    end

    test "slash" do
      assert tokenize("/") == [symbol: "/"]
    end
  end

  describe "string" do
    test "ASCI alphabet lowercase" do
      markup = "abcdefghijklmnopqrstuvwxyz"
      assert tokenize(markup) == [string: markup]
    end

    test "ASCI alphabet uppercase" do
      markup = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      assert tokenize(markup) == [string: markup]
    end

    test "digits" do
      markup = "1234567890"
      assert tokenize(markup) == [string: markup]
    end

    test "UTF-8 characters" do
      markup = "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"
      assert tokenize(markup) == [string: markup]
    end

    test "special characters" do
      markup = "§£@^&*()_+[];:|~,.?"
      assert tokenize(markup) == [string: markup]
    end
  end

  describe "token combinations" do
    test "whitespace, symbol" do
      markup = "\n{"
      assert tokenize(markup) == [whitespace: "\n", symbol: "{"]
    end

    test "whitespace, string" do
      markup = "\nabc"
      assert tokenize(markup) == [whitespace: "\n", string: "abc"]
    end

    test "symbol, whitespace" do
      markup = "{\n"
      assert tokenize(markup) == [symbol: "{", whitespace: "\n"]
    end

    test "symbol, string" do
      markup = "{abc"
      assert tokenize(markup) == [symbol: "{", string: "abc"]
    end

    test "string, whitespace" do
      markup = "abc\n"
      assert tokenize(markup) == [string: "abc", whitespace: "\n"]
    end

    test "string, symbol" do
      markup = "abc{"
      assert tokenize(markup) == [string: "abc", symbol: "{"]
    end
  end
end
