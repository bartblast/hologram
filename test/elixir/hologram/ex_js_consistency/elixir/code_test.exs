defmodule Hologram.ExJsConsistency.Elixir.CodeTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/code_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "ensure_compiled/1" do
    test "compiled module" do
      assert Code.ensure_compiled(String.Chars) == {:module, String.Chars}
    end

    test "not compiled, non-existing module" do
      assert Code.ensure_compiled(MyModule) == {:error, :nofile}
    end

    test "raises FunctionClauseError if the argument is not an atom" do
      assert_raise FunctionClauseError,
                   "no function clause matching in Code.ensure_compiled/1",
                   fn ->
                     Code.ensure_compiled(1)
                   end
    end
  end
end
