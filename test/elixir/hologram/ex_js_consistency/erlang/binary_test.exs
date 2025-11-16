defmodule Hologram.ExJsConsistency.Erlang.BinaryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/binary_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "at/2" do
    test "returns byte at position 0" do
      assert :binary.at(<<5, 19, 72, 33>>, 0) == 5
    end

    test "returns byte at position 1" do
      assert :binary.at(<<5, 19, 72, 33>>, 1) == 19
    end

    test "raises ArgumentError when position is out of range" do
      assert_error ArgumentError, "argument error", fn ->
        :binary.at(<<5, 19, 72, 33>>, 4)
      end
    end

    test "single element binary from text" do
      assert :binary.at("a", 0) == 97
    end

    test "multi-byte binary from text, first position" do
      assert :binary.at("hello", 0) == 104
    end

    test "multi-byte binary from text, middle position" do
      assert :binary.at("hello", 2) == 108
    end

    test "multi-byte binary from text, last position" do
      assert :binary.at("hello", 4) == 111
    end

    test "longer text binary" do
      assert :binary.at("The quick brown fox jumps over the lazy dog", 16) == 102
    end

    test "very long text binary" do
      long_text =
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " <>
          "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " <>
          "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris " <>
          "nisi ut aliquip ex ea commodo consequat."

      assert :binary.at(long_text, 100) == 101
    end

    test "binary with Unicode emoji at ASCII position" do
      # Position 6 is the first byte of the emoji (UTF-8 encoded)
      assert :binary.at("Hello 😀 World", 6) == 0xF0
    end

    test "binary with Unicode emoji, position after emoji" do
      # The emoji takes 4 bytes in UTF-8, so '!' is at position 6
      assert :binary.at("Hi😀!", 6) == 33
    end

    test "binary with multiple Unicode characters" do
      # First byte of the second emoji (🎊)
      assert :binary.at("🎉🎊🎈", 4) == 0xF0
    end

    test "binary with mixed ASCII and Unicode" do
      # Position 5 should be the first byte of the Chinese character '测'
      assert :binary.at("Test 测试 🔬", 5) == 0xE6
    end

    test "binary with various Unicode symbols" do
      assert :binary.at("♠♣♥♦", 0) == 0xE2
    end

    test "binary with Unicode combining characters" do
      # é = e + combining acute accent
      assert :binary.at("Café", 3) == 0xC3
    end

    test "binary from bits, valid byte boundary" do
      # 65 = 'A'
      assert :binary.at(<<0::1, 1::1, 0::1, 0::1, 0::1, 0::1, 0::1, 1::1>>, 0) == 65
    end

    test "binary from multiple bytes in bits" do
      subject = <<
        0::1,
        1::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        1::1,
        # 65 = 'A'
        0::1,
        1::1,
        0::1,
        0::1,
        0::1,
        0::1,
        1::1,
        0::1,
        # 66 = 'B'
        0::1,
        1::1,
        0::1,
        0::1,
        0::1,
        0::1,
        1::1,
        1::1
        # 67 = 'C'
      >>

      assert :binary.at(subject, 1) == 66
    end

    test "first arg is a bitstring from bits, but not a binary" do
      subject = <<1::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   fn ->
                     :binary.at(subject, 0)
                   end
    end

    test "second arg is a negative integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   fn ->
                     :binary.at("a", -1)
                   end
    end

    test "second arg exceeds bounds" do
      assert_error ArgumentError,
                   "argument error",
                   fn ->
                     :binary.at("a", 2)
                   end
    end

    test "second arg at exact boundary (one past last index)" do
      assert_error ArgumentError,
                   "argument error",
                   fn ->
                     :binary.at("test", 4)
                   end
    end

    test "second arg far exceeds bounds" do
      assert_error ArgumentError,
                   "argument error",
                   fn ->
                     :binary.at("hi", 1000)
                   end
    end

    test "empty binary from text" do
      assert_error ArgumentError,
                   "argument error",
                   fn ->
                     :binary.at("", 0)
                   end
    end

    test "empty binary from bits" do
      assert_error ArgumentError,
                   "argument error",
                   fn ->
                     :binary.at(<<>>, 0)
                   end
    end

    test "position is zero for valid binary" do
      assert :binary.at("xyz", 0) == 120
    end

    test "binary with null byte" do
      # null byte
      assert :binary.at(<<0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>, 0) == 0
    end

    test "binary with all bits set" do
      # 255
      assert :binary.at(<<1::1, 1::1, 1::1, 1::1, 1::1, 1::1, 1::1, 1::1>>, 0) == 255
    end

    test "binary with mixed null and non-null bytes" do
      subject = <<
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        # null byte
        0::1,
        1::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        1::1,
        # 65 = 'A'
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1,
        0::1
        # null byte
      >>

      assert :binary.at(subject, 2) == 0
    end

    test "first arg is not a bitstring (integer)" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   fn ->
                     :binary.at(123, 0)
                   end
    end

    test "first arg is not a bitstring (atom)" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   fn ->
                     :binary.at(:test, 0)
                   end
    end

    test "first arg is not a bitstring (list)" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   fn ->
                     :binary.at([1, 2], 0)
                   end
    end

    test "second arg is not an integer (atom)" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn ->
                     :binary.at("test", :zero)
                   end
    end

    test "second arg is not an integer (float)" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn ->
                     :binary.at("test", 0.0)
                   end
    end

    test "second arg is zero (edge case for valid position)" do
      assert :binary.at("a", 0) == 97
    end

    test "binary with only whitespace" do
      assert :binary.at("   ", 1) == 32
    end

    test "binary with newline and tab characters" do
      assert :binary.at("a\n\tb", 1) == 10
    end

    test "binary with special characters" do
      assert :binary.at("!@#$%^&*()", 5) == 94
    end

    test "single byte binary from bits with maximum value" do
      # 255
      assert :binary.at(<<1::1, 1::1, 1::1, 1::1, 1::1, 1::1, 1::1, 1::1>>, 0) == 255
    end

    test "single byte binary from bits with minimum value" do
      # 0
      assert :binary.at(<<0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1, 0::1>>, 0) == 0
    end
  end
end
