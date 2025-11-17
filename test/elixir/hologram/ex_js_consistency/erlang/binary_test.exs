defmodule Elixir.Hologram.ExJsConsistency.Erlang.BinaryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/binary_test.mjs
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "first/1" do
    test "raises ArgumentError if the first argument is integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [1]}
    end

    test "raises ArgumentError if the first argument is a float" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [3.14]}
    end

    test "raises ArgumentError if the first argument is an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [:test]}
    end

    test "raises ArgumentError if the first argument is a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [[1, 2, 3]]}
    end

    test "raises ArgumentError if the first argument is a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [{1, 2}]}
    end

    test "raises ArgumentError if the first argument is a map" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [%{key: :value}]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstringg" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :first, [<<1::1, 0::1, 1::1>>]}
    end

    test "raises ArgumentError if the first argument is a zero-sized binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :first, [<<>>]}
    end

    test "raises ArgumentError if the first argument is a zero-sized text" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :first, [""]}
    end

    test "return first byte of a binary" do
      assert :binary.first(<<5, 4, 3>>) == 5
    end

    test "returns first byte of a text-based bitstring" do
      assert :binary.first("ELIXIR") == 69
    end

    test "returns first byte of a single-byte binary" do
      assert :binary.first(<<42>>) == 42
    end

    test "returns first byte of a single-character text" do
      assert :binary.first("Z") == 90
    end

    test "returns first byte of a large binary" do
      large_binary = <<123>> <> :binary.copy(<<0>>, 999)
      assert :binary.first(large_binary) == 123
    end

    test "returns first byte of binary created from float literal" do
      assert :binary.first(<<3.14>>) == 64
    end

    test "returns 0 when byte value wraps around (256 mod 256)" do
      assert :binary.first(<<256>>) == 0
    end

    test "returns 255 when first byte is -1 (two's complement wraparound)" do
      assert :binary.first(<<-1, 43>>) == 255
    end

    test "returns first byte of UTF-8 multi-byte character" do
      assert :binary.first("é") == 195
    end
  end
end
