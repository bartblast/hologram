defmodule Hologram.Compiler.ParserTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Compiler.Parser

  describe "parse/1" do
    test "valid code" do
      assert Parser.parse("1 + 2") == {:ok, {:+, [line: 1], [1, 2]}}
    end

    test "invalid code" do
      assert Parser.parse(".1") ==
               {:error, {[line: 1, column: 1], "syntax error before: ", "'.'"}}
    end
  end
end
