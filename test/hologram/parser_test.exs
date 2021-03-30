defmodule Hologram.ParserTest do
  use ExUnit.Case
  alias Hologram.Transpiler.Parser

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

  describe "parse_file/1" do
    test "valid code" do
      assert {:ok, _} = Parser.parse_file("lib/hologram/transpiler/transformer.ex")
    end

    test "invalid code" do
      assert {:error, _} = Parser.parse_file("README.md")
    end
  end

  describe "parse_file!/1" do
    test "valid code" do
      assert {:defmodule, _, _} = Parser.parse_file!("lib/hologram/transpiler/transformer.ex")
    end

    test "invalid code" do
      assert_raise RuntimeError, "Invalid code", fn ->
        Parser.parse_file!("README.md")
      end
    end
  end
end
