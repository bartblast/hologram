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
    test "returns a tuple for a single binary" do
      compiled_pattern = :binary.compile_pattern("hello")
      assert is_tuple(compiled_pattern)
    end

    test "returns a tuple for a list of binaries" do
      compiled_pattern = :binary.compile_pattern(["hello", "world"])
      assert is_tuple(compiled_pattern)
    end

    test "returns a tuple for a compiled pattern" do
      base_pattern = :binary.compile_pattern("hello")
      # At the moment its imposible to make this work
      # see: https://github.com/bartblast/hologram/pull/374#issuecomment-3578359261
      #
      # compiled_pattern = :binary.compile_pattern(base_pattern)
      # assert is_tuple(compiled_pattern)

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(base_pattern) end
    end

    test "uses Boyer-Moore algorithm for single patterns" do
      compiled_pattern = :binary.compile_pattern("hello")
      assert elem(compiled_pattern, 0) == :bm
      assert is_reference(elem(compiled_pattern, 1))
    end

    test "uses Aro-Corsick algorithm for multiple patterns" do
      compiled_pattern = :binary.compile_pattern(["hello", "world"])
      assert elem(compiled_pattern, 0) == :ac
      assert is_reference(elem(compiled_pattern, 1))
    end

    test "raises ArgumentError when pattern is not a binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(123) end
    end

    test "raises ArgumentError when pattern is an empty list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern([]) end
    end

    test "raises ArgumentError when pattern is a list but contains non-binary elements" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(["hello", 123]) end
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
end
