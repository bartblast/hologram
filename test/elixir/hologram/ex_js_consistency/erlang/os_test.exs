defmodule Hologram.ExJsConsistency.Erlang.OsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/os_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  import Hologram.Commons.TestUtils

  @moduletag :consistency

  describe "system_time/0" do
    test "returns an integer" do
      result = :os.system_time()
      assert is_integer(result)
    end

    test "returns a positive integer" do
      result = :os.system_time()
      assert result > 0
    end

    test "returns nanoseconds since epoch" do
      result = :os.system_time()
      now = System.os_time(:nanosecond)
      # Allow 100ms (100000000 nanoseconds) difference for test execution
      assert abs(result - now) < 100_000_000
    end
  end

  describe "system_time/1" do
    test "returns an integer with millisecond atom unit" do
      result = :os.system_time(:millisecond)
      assert is_integer(result)
      assert result > 0
    end

    test "returns milliseconds with millisecond atom unit" do
      result = :os.system_time(:millisecond)
      now = System.os_time(:millisecond)
      # Allow 100ms difference
      assert abs(result - now) < 100
    end

    test "returns an integer with second atom unit" do
      result = :os.system_time(:second)
      assert is_integer(result)
      assert result > 0
    end

    test "returns seconds with second atom unit" do
      result = :os.system_time(:second)
      now = System.os_time(:second)
      # Allow 1 second difference
      assert abs(result - now) <= 1
    end

    test "returns an integer with microsecond atom unit" do
      result = :os.system_time(:microsecond)
      assert is_integer(result)
      assert result > 0
    end

    test "returns microseconds with microsecond atom unit" do
      result = :os.system_time(:microsecond)
      now = System.os_time(:microsecond)
      # Allow 100000 microseconds (100ms) difference
      assert abs(result - now) < 100_000
    end

    test "returns an integer with nanosecond atom unit" do
      result = :os.system_time(:nanosecond)
      assert is_integer(result)
      assert result > 0
    end

    test "returns nanoseconds with nanosecond atom unit" do
      result = :os.system_time(:nanosecond)
      now = System.os_time(:nanosecond)
      # Allow 100ms (100000000 nanoseconds) difference
      assert abs(result - now) < 100_000_000
    end

    test "returns an integer with native atom unit" do
      result = :os.system_time(:native)
      assert is_integer(result)
      assert result > 0
    end

    test "returns nanoseconds with native atom unit" do
      result = :os.system_time(:native)
      now = System.os_time(:nanosecond)
      # Allow 100ms (100000000 nanoseconds) difference
      assert abs(result - now) < 100_000_000
    end

    test "returns an integer with perf_counter atom unit" do
      result = :os.system_time(:perf_counter)
      assert is_integer(result)
      assert result > 0
    end

    test "returns epoch-based nanoseconds with perf_counter atom unit" do
      result = :os.system_time(:perf_counter)
      now = System.os_time(:nanosecond)
      # Allow 100ms (100000000 nanoseconds) difference for test execution
      # perf_counter should be epoch-based like other units
      assert abs(result - now) < 100_000_000
    end

    test "returns an integer with numeric unit" do
      result = :os.system_time(1000)
      assert is_integer(result)
      assert result > 0
    end

    test "returns milliseconds with numeric unit 1000 (parts per second)" do
      result = :os.system_time(1000)
      now = System.os_time(:millisecond)
      # Allow 100ms difference
      assert abs(result - now) < 100
    end

    test "returns seconds with numeric unit 1" do
      result = :os.system_time(1)
      now = System.os_time(:second)
      # Allow 1 second difference
      assert abs(result - now) <= 1
    end

    test "returns nanoseconds with numeric unit 1000000000" do
      result = :os.system_time(1_000_000_000)
      now = System.os_time(:nanosecond)
      # Allow 100ms (100000000 nanoseconds) difference
      assert abs(result - now) < 100_000_000
    end

    test "raises ArgumentError if unit is not an atom or integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [[]]}
    end

    test "raises ArgumentError if unit atom is invalid" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [:invalid_unit]}
    end

    test "raises ArgumentError if unit is a float" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [1.5]}
    end

    test "raises ArgumentError if unit is a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, ["test"]}
    end

    test "raises ArgumentError if unit is a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [{:test}]}
    end

    test "raises ArgumentError if unit is zero integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [0]}
    end

    test "raises ArgumentError if unit is negative integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [-1]}
    end
  end
end
