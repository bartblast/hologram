defmodule Hologram.ExJsConsistency.Erlang.CodeTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/code_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe "ensure_loaded/1" do
    test "loaded module" do
      assert :code.ensure_loaded(String.Chars) == {:module, String.Chars}
    end

    test "not loaded, non-existing module" do
      assert :code.ensure_loaded(MyModule) == {:error, :nofile}
    end

    test "raises FunctionClauseError if the argument is not an atom" do
      assert_raise FunctionClauseError,
                   "no function clause matching in :code.ensure_loaded/1",
                   fn ->
                     :code.ensure_loaded(1)
                   end
    end
  end
end
