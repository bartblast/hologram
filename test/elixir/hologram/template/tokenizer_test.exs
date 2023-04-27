defmodule Hologram.Template.TokenizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Tokenizer

  test "empty" do
    assert tokenize("") == []
  end

  test "whitespaces" do
    assert tokenize("aaa \\\n\r\t\\bbb \\\n\r\t\\") == [
             string: "aaa",
             whitespace: " ",
             symbol: "\\",
             whitespace: "\n",
             whitespace: "\r",
             whitespace: "\t",
             symbol: "\\",
             string: "bbb",
             whitespace: " ",
             symbol: "\\",
             whitespace: "\n",
             whitespace: "\r",
             whitespace: "\t",
             symbol: "\\"
           ]
  end

  test "elixir interpolation" do
    assert tokenize("aaa\\\#{bbb\#{ccc#ddd{eee\\fff\\\#{ggg\#{hhh#iii{jjj\\") == [
             string: "aaa",
             symbol: "\\#",
             symbol: "{",
             string: "bbb",
             symbol: "\#{",
             string: "ccc",
             symbol: "#",
             string: "ddd",
             symbol: "{",
             string: "eee",
             symbol: "\\",
             string: "fff",
             symbol: "\\#",
             symbol: "{",
             string: "ggg",
             symbol: "\#{",
             string: "hhh",
             symbol: "#",
             string: "iii",
             symbol: "{",
             string: "jjj",
             symbol: "\\"
           ]
  end

  test "javascript interpolation" do
    assert tokenize("aaa\\${bbb${ccc$ddd{eee\\fff\\${ggg${hhh$iii{jjj\\") == [
             string: "aaa",
             symbol: "\\$",
             symbol: "{",
             string: "bbb",
             symbol: "${",
             string: "ccc",
             symbol: "$",
             string: "ddd",
             symbol: "{",
             string: "eee",
             symbol: "\\",
             string: "fff",
             symbol: "\\$",
             symbol: "{",
             string: "ggg",
             symbol: "${",
             string: "hhh",
             symbol: "$",
             string: "iii",
             symbol: "{",
             string: "jjj",
             symbol: "\\"
           ]
  end

  test "equal sign" do
    assert tokenize("aaa=bbb=") == [
             string: "aaa",
             symbol: "=",
             string: "bbb",
             symbol: "="
           ]
  end

  test "double quotes" do
    assert tokenize(~s(aaa\\"bbb"ccc\\ddd\\"eee"fff\\)) == [
             string: "aaa",
             symbol: "\\\"",
             string: "bbb",
             symbol: "\"",
             string: "ccc",
             symbol: "\\",
             string: "ddd",
             symbol: "\\\"",
             string: "eee",
             symbol: "\"",
             string: "fff",
             symbol: "\\"
           ]
  end

  test "single quotes" do
    assert tokenize("aaa\\'bbb'ccc\\ddd\\'eee'fff\\") == [
             string: "aaa",
             symbol: "\\'",
             string: "bbb",
             symbol: "'",
             string: "ccc",
             symbol: "\\",
             string: "ddd",
             symbol: "\\'",
             string: "eee",
             symbol: "'",
             string: "fff",
             symbol: "\\"
           ]
  end

  test "backticks" do
    assert tokenize("aaa\\`bbb`ccc\\ddd\\`eee`fff\\ggg") == [
             string: "aaa",
             symbol: "\\`",
             string: "bbb",
             symbol: "`",
             string: "ccc",
             symbol: "\\",
             string: "ddd",
             symbol: "\\`",
             string: "eee",
             symbol: "`",
             string: "fff",
             symbol: "\\",
             string: "ggg"
           ]
  end

  describe "curly braces" do
    test "opening" do
      assert tokenize("aaa\\{bbb{ccc\\ddd\\{eee{fff\\ggg") == [
               string: "aaa",
               symbol: "\\{",
               string: "bbb",
               symbol: "{",
               string: "ccc",
               symbol: "\\",
               string: "ddd",
               symbol: "\\{",
               string: "eee",
               symbol: "{",
               string: "fff",
               symbol: "\\",
               string: "ggg"
             ]
    end

    test "closing" do
      assert tokenize("aaa\\}bbb}ccc\\ddd\\}eee}fff\\ggg") == [
               string: "aaa",
               symbol: "\\}",
               string: "bbb",
               symbol: "}",
               string: "ccc",
               symbol: "\\",
               string: "ddd",
               symbol: "\\}",
               string: "eee",
               symbol: "}",
               string: "fff",
               symbol: "\\",
               string: "ggg"
             ]
    end
  end

  describe "raw block" do
    test "start" do
      assert tokenize(
               "aaa\\{#raw}bbb{\\#raw}ccc{#raw}ddd\\{#eee{#fff\\ggg\\{#raw}hhh{\\#raw}iii{#raw}jjj\\{#kkk{#lll\\"
             ) == [
               string: "aaa",
               symbol: "\\{",
               symbol: "#",
               string: "raw",
               symbol: "}",
               string: "bbb",
               symbol: "{",
               symbol: "\\#",
               string: "raw",
               symbol: "}",
               string: "ccc",
               symbol: "{#raw}",
               string: "ddd",
               symbol: "\\{",
               symbol: "#",
               string: "eee",
               symbol: "{#",
               string: "fff",
               symbol: "\\",
               string: "ggg",
               symbol: "\\{",
               symbol: "#",
               string: "raw",
               symbol: "}",
               string: "hhh",
               symbol: "{",
               symbol: "\\#",
               string: "raw",
               symbol: "}",
               string: "iii",
               symbol: "{#raw}",
               string: "jjj",
               symbol: "\\{",
               symbol: "#",
               string: "kkk",
               symbol: "{#",
               string: "lll",
               symbol: "\\"
             ]
    end

    test "end" do
      assert tokenize(
               "aaa\\{/raw}bbb{/raw}ccc\\{/ddd{/eee\\fff\\{/raw}ggg{/raw}hhh\\{/iii{/jjj\\"
             ) == [
               string: "aaa",
               symbol: "\\{",
               symbol: "/",
               string: "raw",
               symbol: "}",
               string: "bbb",
               symbol: "{/raw}",
               string: "ccc",
               symbol: "\\{",
               symbol: "/",
               string: "ddd",
               symbol: "{/",
               string: "eee",
               symbol: "\\",
               string: "fff",
               symbol: "\\{",
               symbol: "/",
               string: "raw",
               symbol: "}",
               string: "ggg",
               symbol: "{/raw}",
               string: "hhh",
               symbol: "\\{",
               symbol: "/",
               string: "iii",
               symbol: "{/",
               string: "jjj",
               symbol: "\\"
             ]
    end
  end

  describe "non-raw block" do
    test "start" do
      assert tokenize(
               "aaa\\{#xxx}bbb{\\#xxx}ccc{#xxx}ddd\\{#eee{#fff\\ggg\\{#xxx}hhh{\\#xxx}iii{#xxx}jjj\\{#kkk{#lll\\"
             ) == [
               string: "aaa",
               symbol: "\\{",
               symbol: "#",
               string: "xxx",
               symbol: "}",
               string: "bbb",
               symbol: "{",
               symbol: "\\#",
               string: "xxx",
               symbol: "}",
               string: "ccc",
               symbol: "{#",
               string: "xxx",
               symbol: "}",
               string: "ddd",
               symbol: "\\{",
               symbol: "#",
               string: "eee",
               symbol: "{#",
               string: "fff",
               symbol: "\\",
               string: "ggg",
               symbol: "\\{",
               symbol: "#",
               string: "xxx",
               symbol: "}",
               string: "hhh",
               symbol: "{",
               symbol: "\\#",
               string: "xxx",
               symbol: "}",
               string: "iii",
               symbol: "{#",
               string: "xxx",
               symbol: "}",
               string: "jjj",
               symbol: "\\{",
               symbol: "#",
               string: "kkk",
               symbol: "{#",
               string: "lll",
               symbol: "\\"
             ]
    end

    test "end" do
      assert tokenize(
               "aaa\\{/xxx}bbb{/xxx}ccc\\{/ddd{/eee\\fff\\{/xxx}ggg{/xxx}hhh\\{/iii{/jjj\\"
             ) == [
               string: "aaa",
               symbol: "\\{",
               symbol: "/",
               string: "xxx",
               symbol: "}",
               string: "bbb",
               symbol: "{/",
               string: "xxx",
               symbol: "}",
               string: "ccc",
               symbol: "\\{",
               symbol: "/",
               string: "ddd",
               symbol: "{/",
               string: "eee",
               symbol: "\\",
               string: "fff",
               symbol: "\\{",
               symbol: "/",
               string: "xxx",
               symbol: "}",
               string: "ggg",
               symbol: "{/",
               string: "xxx",
               symbol: "}",
               string: "hhh",
               symbol: "\\{",
               symbol: "/",
               string: "iii",
               symbol: "{/",
               string: "jjj",
               symbol: "\\"
             ]
    end
  end

  describe "angle brackets" do
    test "opening" do
      assert tokenize("aaa<bbb</ccc/ddd<eee</fff/") == [
               string: "aaa",
               symbol: "<",
               string: "bbb",
               symbol: "</",
               string: "ccc",
               symbol: "/",
               string: "ddd",
               symbol: "<",
               string: "eee",
               symbol: "</",
               string: "fff",
               symbol: "/"
             ]
    end

    test "closing" do
      assert tokenize("aaa>bbb/>ccc/ddd>eee/>fff/") == [
               string: "aaa",
               symbol: ">",
               string: "bbb",
               symbol: "/>",
               string: "ccc",
               symbol: "/",
               string: "ddd",
               symbol: ">",
               string: "eee",
               symbol: "/>",
               string: "fff",
               symbol: "/"
             ]
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
