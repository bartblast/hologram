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
      assert tokenize("</.<./") == [
               symbol: "</",
               string: ".",
               symbol: "<",
               string: ".",
               symbol: "/"
             ]
    end

    test "closing" do
      assert tokenize("/>.>./") == [
               symbol: "/>",
               string: ".",
               symbol: ">",
               string: ".",
               symbol: "/"
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

  describe "blocks" do
    test "raw" do
      assert tokenize("{$raw}.\\{$raw}.{\\$raw}.{$raw\\}") == [
               symbol: "{$raw}",
               string: ".",
               symbol: "\\{",
               symbol: "$",
               string: "raw",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "\\$",
               string: "raw",
               symbol: "}",
               string: ".",
               symbol: "{$",
               string: "raw",
               symbol: "\\}"
             ]
    end

    test "end" do
      assert tokenize("{$end}.\\{$end}.{\\$end}.{$end\\}") == [
               symbol: "{$end}",
               string: ".",
               symbol: "\\{",
               symbol: "$",
               string: "end",
               symbol: "}",
               string: ".",
               symbol: "{",
               symbol: "\\$",
               string: "end",
               symbol: "}",
               string: ".",
               symbol: "{$",
               string: "end",
               symbol: "\\}"
             ]
    end

    test "case" do
      assert tokenize("{$case.\\{$case.{\\$case") == [
               symbol: "{$case",
               string: ".",
               symbol: "\\{",
               symbol: "$",
               string: "case.",
               symbol: "{",
               symbol: "\\$",
               string: "case"
             ]
    end

    test "for" do
      assert tokenize("{$for.\\{$for.{\\$for") == [
               symbol: "{$for",
               string: ".",
               symbol: "\\{",
               symbol: "$",
               string: "for.",
               symbol: "{",
               symbol: "\\$",
               string: "for"
             ]
    end

    test "if" do
      assert tokenize("{$if.\\{$if.{\\$if") == [
               symbol: "{$if",
               string: ".",
               symbol: "\\{",
               symbol: "$",
               string: "if.",
               symbol: "{",
               symbol: "\\$",
               string: "if"
             ]
    end

    test "subblock" do
      assert tokenize("{$.{.\\{$.{\\$") == [
               symbol: "{$",
               string: ".",
               symbol: "{",
               string: ".",
               symbol: "\\{",
               symbol: "$",
               string: ".",
               symbol: "{",
               symbol: "\\$"
             ]
    end
  end

  describe "other symbols" do
    test "equal sign" do
      assert tokenize("=") == [symbol: "="]
    end

    test "slash" do
      assert tokenize("/") == [symbol: "/"]
    end

    test "backslash" do
      assert tokenize("\\") == [symbol: "\\"]
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
      markup = "§£@%^&*()-_+[];:|~,.?"
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
