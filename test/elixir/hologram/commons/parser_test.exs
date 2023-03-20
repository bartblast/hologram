defmodule Hologram.Commons.ParserTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Test.Fixtures.Commons.Parser.Implementation

  @error_message "Invalid code:\n-----\ninvalid_code\n-----\n"
  @invalid_code_file_path "#{@fixtures_path}/commons/parser/file_2.txt"
  @valid_code_file_path "#{@fixtures_path}/commons/parser/file_1.txt"

  describe "parse!/1" do
    test "valid code" do
      assert Implementation.parse!("valid_code") == :dummy_result
    end

    test "invalid code" do
      assert_raise RuntimeError, @error_message, fn ->
        Implementation.parse!("invalid_code")
      end
    end
  end

  describe "parse_file/1" do
    test "valid code" do
      assert {:ok, :dummy_result} = Implementation.parse_file(@valid_code_file_path)
    end

    test "invalid code" do
      assert {:error, :dummy_error_details} = Implementation.parse_file(@invalid_code_file_path)
    end
  end

  describe "parse_file!/1" do
    test "valid code" do
      assert Implementation.parse_file!(@valid_code_file_path) == :dummy_result
    end

    test "invalid code" do
      assert_raise RuntimeError, @error_message, fn ->
        Implementation.parse_file!(@invalid_code_file_path)
      end
    end
  end
end
