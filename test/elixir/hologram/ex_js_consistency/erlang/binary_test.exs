defmodule Hologram.ExJsConsistency.Erlang.BinaryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/binary_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @binary <<5, 19, 72, 33>>

  describe "at/2" do
    test "returns first byte" do
      assert :binary.at(@binary, 0) == 5
    end

    test "returns middle byte" do
      assert :binary.at(@binary, 1) == 19
    end

    test "returns last byte" do
      assert :binary.at(@binary, 3) == 33
    end

    test "raises ArgumentError when position is out of range" do
      assert_error ArgumentError, "argument error", fn ->
        :binary.at(@binary, 4)
      end
    end

    test "raises ArgumentError when subject is nil" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   fn -> :binary.at(nil, 0) end
    end

    test "raises ArgumentError when bitstring is not a binary" do
      subject = <<1::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   fn -> :binary.at(subject, 0) end
    end

    test "raises ArgumentError when position is nil" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn -> :binary.at(@binary, nil) end
    end

    test "raises ArgumentError when position is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   fn -> :binary.at(@binary, -1) end
    end
  end

  describe "compile_pattern/1" do
    # With valid input

    test "single binary pattern returns Boyer-Moore compiled pattern tuple" do
      result = :binary.compile_pattern("Hello")

      assert is_tuple(result)
      assert elem(result, 0) == :bm
      assert is_reference(elem(result, 1))
    end

    test "list of binary patterns returns Aho-Corasick compiled pattern tuple" do
      result = :binary.compile_pattern(["He", "llo"])

      assert is_tuple(result)
      assert elem(result, 0) == :ac
      assert is_reference(elem(result, 1))
    end

    test "list with single element returns Boyer-Moore compiled pattern tuple" do
      result = :binary.compile_pattern(["Hello"])

      assert is_tuple(result)
      assert elem(result, 0) == :bm
      assert is_reference(elem(result, 1))
    end

    # Errors with direct pattern

    test "raises ArgumentError when pattern is not bitstring" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern(1) end
    end

    test "raises ArgumentError when pattern is non-binary bitstring" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern(<<1::1, 0::1, 1::1>>) end
    end

    test "raises ArgumentError when pattern is empty binary" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern("") end
    end

    test "raises ArgumentError when pattern is empty list" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern([]) end
    end

    # Errors with list containing invalid item

    test "raises ArgumentError when pattern is list containing non-bitstring" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern(["Hello", 1]) end
    end

    test "raises ArgumentError when pattern is list containing non-binary bitstring" do
      assert_raise ArgumentError, fn ->
        :binary.compile_pattern(["Hello", <<1::1, 0::1, 1::1>>])
      end
    end

    test "raises ArgumentError when pattern is list containing empty binary" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern(["Hello", ""]) end
    end

    test "raises ArgumentError when pattern is list containing empty list" do
      assert_raise ArgumentError, fn -> :binary.compile_pattern(["Hello", []]) end
    end
  end

  describe "copy/2" do
    test "text-based, empty binary, zero times" do
      assert :binary.copy("", 0) == ""
    end

    test "text-based, empty binary, one time" do
      assert :binary.copy("", 1) == ""
    end

    test "text-based, empty binary, multiple times" do
      assert :binary.copy("", 3) == ""
    end

    test "text-based, non-empty binary, zero times" do
      assert :binary.copy("hello", 0) == ""
    end

    test "text-based, non-empty binary, one time" do
      assert :binary.copy("hello", 1) == "hello"
    end

    test "text-based, non-empty binary, multiple times" do
      assert :binary.copy("hello", 3) == "hellohellohello"
    end

    test "bytes-based, empty binary, zero times" do
      assert :binary.copy(<<>>, 0) == <<>>
    end

    test "bytes-based, empty binary, one time" do
      assert :binary.copy(<<>>, 1) == <<>>
    end

    test "bytes-based, empty binary, multiple times" do
      assert :binary.copy(<<>>, 3) == <<>>
    end

    test "bytes-based, non-empty binary, zero times" do
      assert :binary.copy(<<65, 66, 67>>, 0) == <<>>
    end

    test "bytes-based, non-empty binary, one time" do
      assert :binary.copy(<<65, 66, 67>>, 1) == <<65, 66, 67>>
    end

    test "bytes-based, non-empty binary, multiple times" do
      result = :binary.copy(<<65, 66, 67>>, 3)
      expected = <<65, 66, 67, 65, 66, 67, 65, 66, 67>>

      assert result == expected
    end

    test "raises ArgumentError if the first argument is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :copy, [:abc, 3]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :copy, [<<1::1, 0::1, 1::1>>, 3]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   {:binary, :copy, ["hello", :abc]}
    end

    test "raises ArgumentError if count is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:binary, :copy, ["hello", -1]}
    end
  end

  describe "first/1" do
    test "returns first byte of a single-byte binary" do
      assert :binary.first(<<42>>) == 42
    end

    test "returns first byte of a multi-byte binary" do
      assert :binary.first(<<5, 4, 3>>) == 5
    end

    test "returns first byte of a text-based binary" do
      assert :binary.first("ELIXIR") == 69
    end

    test "returns first byte of UTF-8 multi-byte character" do
      assert :binary.first("é") == 195
    end

    test "raises ArgumentError if subject is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [123]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :first, [<<1::1, 0::1, 1::1>>]}
    end

    test "raises ArgumentError if subject is an empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :first, [<<>>]}
    end
  end

  describe "last/1" do
    test "returns last byte of a single-byte binary" do
      assert :binary.last(<<42>>) == 42
    end

    test "returns last byte of a multi-byte binary" do
      assert :binary.last(@binary) == 33
    end

    test "returns last byte of a text-based binary" do
      assert :binary.last("ELIXIR") == 82
    end

    test "returns last byte of UTF-8 multi-byte character" do
      assert :binary.last("é") == 169
    end

    test "raises ArgumentError if subject is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :last, [:abc]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :last, [<<1::1, 0::1, 1::1>>]}
    end

    test "raises ArgumentError if subject is an empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :last, [""]}
    end
  end

  describe "part/2" do
    test "returns part of binary with tuple {start, length}" do
      result = :binary.part("hello world", {0, 5})
      assert result == "hello"
    end

    test "returns middle part with tuple" do
      result = :binary.part("hello world", {6, 5})
      assert result == "world"
    end

    test "returns empty binary when length is 0" do
      result = :binary.part("hello", {0, 0})
      assert result == ""
    end

    test "returns last character" do
      result = :binary.part("hello", {4, 1})
      assert result == "o"
    end

    test "handles bytes-based binary" do
      result = :binary.part(<<72, 101, 108, 108, 111>>, {1, 3})
      assert result == "ell"
    end

    test "handles invalid UTF-8 bytes" do
      result = :binary.part(<<0xC3, 0x28, 0x41>>, {0, 3})
      assert result == <<0xC3, 0x28, 0x41>>
    end

    test "raises ArgumentError when subject is not a binary" do
      assert_raise ArgumentError, fn ->
        :binary.part(:notabinary, {0, 1})
      end
    end

    test "raises ArgumentError when subject is a non-binary bitstring" do
      assert_raise ArgumentError, fn ->
        :binary.part(<<1::1, 0::1, 1::1>>, {0, 1})
      end
    end

    test "raises ArgumentError when posLen is not a tuple" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", [0, 1])
      end
    end

    test "raises ArgumentError when tuple has wrong length" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", {0})
      end
    end

    test "raises ArgumentError when start is not an integer" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", {:invalid, 1})
      end
    end

    test "raises ArgumentError when length is not an integer" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", {0, :invalid})
      end
    end

    test "raises ArgumentError when start is negative" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", {-1, 2})
      end
    end

    test "extracts backwards with negative length" do
      result = :binary.part("hello", {5, -3})
      assert result == "llo"
    end

    test "raises ArgumentError when part extends past end" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", {2, 10})
      end
    end

    test "raises ArgumentError when negative length goes before start" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", {2, -3})
      end
    end
  end

  describe "part/3" do
    test "returns part of binary starting at position with given length" do
      result = :binary.part("hello world", 0, 5)
      assert result == "hello"
    end

    test "returns middle part of binary" do
      result = :binary.part("hello world", 6, 5)
      assert result == "world"
    end

    test "returns empty binary when length is 0" do
      result = :binary.part("hello", 0, 0)
      assert result == ""
    end

    test "returns last character" do
      result = :binary.part("hello", 4, 1)
      assert result == "o"
    end

    test "handles bytes-based binary" do
      result = :binary.part(<<72, 101, 108, 108, 111>>, 1, 3)
      assert result == "ell"
    end

    test "handles invalid UTF-8 bytes" do
      result = :binary.part(<<0xC3, 0x28, 0x41>>, 0, 3)
      assert result == <<0xC3, 0x28, 0x41>>
    end

    test "raises ArgumentError when subject is not a binary" do
      assert_raise ArgumentError, fn ->
        :binary.part(:notabinary, 0, 1)
      end
    end

    test "raises ArgumentError when subject is a non-binary bitstring" do
      assert_raise ArgumentError, fn ->
        :binary.part(<<1::1, 0::1, 1::1>>, 0, 1)
      end
    end

    test "raises ArgumentError when start is not an integer" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", :invalid, 1)
      end
    end

    test "raises ArgumentError when length is not an integer" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", 0, :invalid)
      end
    end

    test "raises ArgumentError when start is negative" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", -1, 2)
      end
    end

    test "extracts backwards with negative length" do
      result = :binary.part("hello", 5, -3)
      assert result == "llo"
    end

    test "raises ArgumentError when part extends past end" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", 2, 10)
      end
    end

    test "raises ArgumentError when negative length goes before start" do
      assert_raise ArgumentError, fn ->
        :binary.part("hello", 2, -3)
      end
    end
  end
end
