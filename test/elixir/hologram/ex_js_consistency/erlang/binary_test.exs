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
    test "copies an empty, text-based binary zero times" do
      assert :binary.copy("", 0) === ""
    end

    test "copies an empty, text-based binary a single time" do
      assert :binary.copy("", 1) === ""
    end

    test "copies an empty, text-based binary multiple times" do
      assert :binary.copy("", 3) === ""
    end

    test "copies an empty, bytes-based binary zero times" do
      binary = <<>>
      assert :binary.copy(binary, 0) === <<>>
    end

    test "copies an empty, bytes-based binary a single time" do
      binary = <<>>
      assert :binary.copy(binary, 1) === <<>>
    end

    test "copies an empty, bytes-based binary multiple times" do
      binary = <<>>
      assert :binary.copy(binary, 3) === <<>>
    end

    test "copies a non-empty, text-based binary zero times" do
      assert :binary.copy("hello", 0) === ""
    end

    test "copies a non-empty, text-based binary a single time" do
      assert :binary.copy("test", 1) === "test"
    end

    test "copies a non-empty, text-based binary multiple times" do
      assert :binary.copy("hello", 3) === "hellohellohello"
    end

    test "copies a non-empty, bytes-based binary zero times" do
      binary = <<65, 66, 67>>
      assert :binary.copy(binary, 0) === <<>>
    end

    test "copies a non-empty, bytes-based binary a single time" do
      binary = <<65, 66, 67>>
      assert :binary.copy(binary, 1) === <<65, 66, 67>>
    end

    test "copies a non-empty, bytes-based binary multiple times" do
      binary = <<65, 66, 67>>
      result = :binary.copy(binary, 2)
      assert result === <<65, 66, 67, 65, 66, 67>>
    end

    test "raises ArgumentError if the first argument is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :copy, [:not_binary, 2]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      bitstring = <<1::3>>

      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :copy, [bitstring, 2]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   {:binary, :copy, ["test", :not_integer]}
    end

    test "raises ArgumentError if count is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:binary, :copy, ["test", -1]}
    end
  end
end
