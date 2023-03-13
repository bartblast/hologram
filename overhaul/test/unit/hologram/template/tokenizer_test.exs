defmodule Hologram.Template.TokenizerTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.Tokenizer

  test "empty" do
    str = ""

    result = Tokenizer.tokenize(str)
    expected = []

    assert result == expected
  end

  test "raw block start" do
    str = "{#raw}"

    result = Tokenizer.tokenize(str)
    expected = [symbol: "{#raw}"]

    assert result == expected
  end

  test "non-raw block start" do
    str = "{#block}"

    result = Tokenizer.tokenize(str)

    expected = [
      symbol: "{#",
      string: "block",
      symbol: "}"
    ]

    assert result == expected
  end

  test "raw block end" do
    str = "{/raw}"

    result = Tokenizer.tokenize(str)
    expected = [symbol: "{/raw}"]

    assert result == expected
  end

  test "non-raw block end" do
    str = "{/block}"

    result = Tokenizer.tokenize(str)

    expected = [
      symbol: "{/",
      string: "block",
      symbol: "}"
    ]

    assert result == expected
  end

  test "whitespaces" do
    str = " \n\r\t \n\r\t"
    result = Tokenizer.tokenize(str)

    expected = [
      whitespace: " ",
      whitespace: "\n",
      whitespace: "\r",
      whitespace: "\t",
      whitespace: " ",
      whitespace: "\n",
      whitespace: "\r",
      whitespace: "\t"
    ]

    assert result == expected
  end

  test "angle brackets" do
    str = "<<///>>"
    result = Tokenizer.tokenize(str)

    expected = [
      symbol: "<",
      symbol: "</",
      symbol: "/",
      symbol: "/>",
      symbol: ">"
    ]

    assert result == expected
  end

  test "double quotes" do
    str = "\"\\\"\""
    result = Tokenizer.tokenize(str)

    expected = [
      symbol: "\"",
      symbol: "\\\"",
      symbol: "\""
    ]

    assert result == expected
  end

  test "curly braces" do
    str = "\\{{\\\\}}"
    result = Tokenizer.tokenize(str)

    expected = [
      symbol: "\\{",
      symbol: "{",
      symbol: "\\",
      symbol: "\\}",
      symbol: "}"
    ]

    assert result == expected
  end

  test "other symbols" do
    str = "\\=/\\=/"
    result = Tokenizer.tokenize(str)

    expected = [
      symbol: "\\",
      symbol: "=",
      symbol: "/",
      symbol: "\\",
      symbol: "=",
      symbol: "/"
    ]

    assert result == expected
  end

  test "strings" do
    str = "abc bcd\ncde\rdef\tefg<fgh>ghi/hij=ijk\"jkl{klm}lmn\\mno"
    result = Tokenizer.tokenize(str)

    expected = [
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
      string: "mno"
    ]

    assert result == expected
  end
end
