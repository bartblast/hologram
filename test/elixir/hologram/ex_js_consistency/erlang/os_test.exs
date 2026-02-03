defmodule Hologram.ExJsConsistency.Erlang.OsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/os_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "system_time/0" do
    test "returns current system time in native time unit (nanoseconds)" do
      before_ns = :os.system_time(:nanosecond)
      result = :os.system_time()
      after_ns = :os.system_time(:nanosecond)

      assert is_integer(result)
      assert result >= before_ns
      assert result <= after_ns
    end
  end

  describe "system_time/1" do
    test "with valid atom unit" do
      assert is_integer(:os.system_time(:second))
    end

    test "with valid integer unit" do
      assert is_integer(:os.system_time(1000))
    end

    test "applies time unit conversion" do
      micro = :os.system_time(:microsecond)
      nano = :os.system_time(:nanosecond)

      # Allow small timing drift between calls
      assert nano >= micro * 999
      assert nano <= micro * 1001 + 1000
    end

    test "raises ArgumentError when argument is not atom or integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [1.0]}
    end

    test "raises ArgumentError when atom argument is not a valid time unit" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [:invalid]}
    end

    test "raises ArgumentError when integer argument is 0" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [0]}
    end

    test "raises ArgumentError when integer argument is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid time unit"),
                   {:os, :system_time, [-1]}
    end
  end

  describe "type/0" do
    test "returns OS family and OS name" do
      assert {family, name} = :os.type()

      assert family in [:win32, :unix]
      assert is_atom(name)
    end
  end
end
