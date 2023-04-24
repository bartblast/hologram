defmodule Hologram.Template.TokenizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Tokenizer

  test "empty" do
    assert tokenize("") == []
  end

  test "raw block start" do
    assert tokenize("{#raw}") == [symbol: "{#raw}"]
  end

  test "non-raw block start" do
    assert tokenize("{#block}") == [
             symbol: "{#",
             string: "block",
             symbol: "}"
           ]
  end

  test "raw block end" do
    assert tokenize("{/raw}") == [symbol: "{/raw}"]
  end

  test "non-raw block end" do
    assert tokenize("{/block}") == [
             symbol: "{/",
             string: "block",
             symbol: "}"
           ]
  end

  test "whitespaces" do
    assert tokenize(" \n\r\t \n\r\t") == [
             whitespace: " ",
             whitespace: "\n",
             whitespace: "\r",
             whitespace: "\t",
             whitespace: " ",
             whitespace: "\n",
             whitespace: "\r",
             whitespace: "\t"
           ]
  end

  test "angle brackets" do
    assert tokenize("<<///>>") == [
             symbol: "<",
             symbol: "</",
             symbol: "/",
             symbol: "/>",
             symbol: ">"
           ]
  end

  test "double quotes" do
    assert tokenize("\"\\\"\"") == [
             symbol: "\"",
             symbol: "\\\"",
             symbol: "\""
           ]
  end

  test "single quotes" do
    assert tokenize("'\\''") == [
             symbol: "'",
             symbol: "\\'",
             symbol: "'"
           ]
  end

  test "curly braces" do
    assert tokenize("\\{{\\\\}}") == [
             symbol: "\\{",
             symbol: "{",
             symbol: "\\",
             symbol: "\\}",
             symbol: "}"
           ]
  end

  test "other symbols" do
    assert tokenize("\\=/\\=/") == [
             symbol: "\\",
             symbol: "=",
             symbol: "/",
             symbol: "\\",
             symbol: "=",
             symbol: "/"
           ]
  end

  test "strings" do
    assert tokenize("abc bcd\ncde\rdef\tefg<fgh>ghi/hij=ijk\"jkl{klm}lmn\\mno'pqr") == [
             string: "abc",
             whitespace: " ",
             string: "bcd",
             whitespace: "\n",
             string: "cde",
             whitespace: "\r",
             string: "def",
             whitespace: "\t",
             string: "efg",
             symbol: "<",
             string: "fgh",
             symbol: ">",
             string: "ghi",
             symbol: "/",
             string: "hij",
             symbol: "=",
             string: "ijk",
             symbol: "\"",
             string: "jkl",
             symbol: "{",
             string: "klm",
             symbol: "}",
             string: "lmn",
             symbol: "\\",
             string: "mno",
             symbol: "'",
             string: "pqr"
           ]
  end
end
