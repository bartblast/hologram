defmodule Graph.UtilsTest do
  use ExUnit.Case, async: true
  alias Hologram.Commons.SystemUtils

  defp sizeof(term) do
    Graph.Utils.sizeof(term)
  end

  test "sizeof/1" do
    assert 64 = sizeof({1, :foo, "bar"})
    assert 8 = sizeof([])
    assert 24 = sizeof([1 | 2])
    assert 56 = sizeof([1, 2, 3])

    expected =
      if SystemUtils.otp_version() >= 27 do
        456
      else
        440
      end

    result = String.duplicate("bar", 128)
    assert sizeof(result) == expected
  end
end
