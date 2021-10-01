defmodule Hologram.Commons.ParserTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Parser

  describe "parse!/1" do
    test "valid code" do
      assert Parser.parse!("1 + 2") == {:+, [line: 1], [1, 2]}
    end

    test "invalid code" do
      assert_raise RuntimeError, ~r/Invalid code/, fn ->
        Parser.parse!(".1")
      end
    end
  end

  describe "parse_file/1" do
    test "valid code" do
      assert {:ok, _} = Parser.parse_file("test/fixtures/commons/file_1.ex")
    end

    test "invalid code" do
      assert {:error, _} = Parser.parse_file("test/fixtures/commons/file_2.txt")
    end
  end

  describe "parse_file!/1" do
    test "valid code" do
      assert Parser.parse_file!("test/fixtures/commons/file_1.ex")
    end

    test "invalid code" do
      assert_raise RuntimeError, ~r/Invalid code/, fn ->
        Parser.parse_file!("test/fixtures/commons/file_2.txt")
      end
    end
  end
end
