defmodule Hologram.Commons.BooleanUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BooleanUtils

  describe "to_integer/1" do
    test "converts false to 0" do
      assert to_integer(false) == 0
    end

    test "converts true to 1" do
      assert to_integer(true) == 1
    end

    test "raises FunctionClauseError for non-boolean" do
      assert_raise FunctionClauseError, fn ->
        nil
        |> wrap_term()
        |> to_integer()
      end
    end
  end
end
