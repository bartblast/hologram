defmodule Hologram.Transpiler.ParserTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Parser

  describe "parse/1" do
    test "valid code" do
      assert {:ok, _} = Parser.parse("1 + 2")
    end

    test "invalid code" do
      assert {:error, _} = Parser.parse(".1")
    end
  end
end
