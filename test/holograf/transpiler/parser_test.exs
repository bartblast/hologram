defmodule Holograf.Transpiler.ParserTest do
  use ExUnit.Case
  alias Holograf.Transpiler.Parser

  describe "parse!/1" do
    test "valid code" do
      assert Parser.parse!("1 + 2") == {:+, [line: 1], [1, 2]}
    end

    test "invalid code" do
      assert_raise RuntimeError, "Invalid code", fn ->
        Parser.parse!(".1")
      end
    end
  end
end
