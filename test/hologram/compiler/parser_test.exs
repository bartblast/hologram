defmodule Hologram.Compiler.ParserTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Parser

  describe "parse/1" do
    test "valid code" do
      assert {:ok, _} = Parser.parse("1 + 2")
    end

    test "invalid code" do
      assert {:error, _} = Parser.parse(".1")
    end
  end
end
