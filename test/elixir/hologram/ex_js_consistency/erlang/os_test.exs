defmodule Hologram.ExJsConsistency.Erlang.OsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/os_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "system_time/0" do
    test "returns current system time in nanoseconds" do
      before_ms = System.os_time(:millisecond)
      result = :os.system_time()
      after_ms = System.os_time(:millisecond)

      assert is_integer(result)
      assert result >= before_ms * 1_000_000
      assert result <= (after_ms + 1) * 1_000_000
    end

    test "returns different values on subsequent calls" do
      result1 = :os.system_time()
      result2 = :os.system_time()

      assert result1 <= result2
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
