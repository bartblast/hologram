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
      assert :binary.last("é") == 195
    end

    test "raises ArgumentError if subject is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :last, [:abc]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :last, [<<1::1, 0::1, 1::1>>, 3]}
    end

    test "raises ArgumentError if subject is an empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :last, [""]}
    end
  end
end
