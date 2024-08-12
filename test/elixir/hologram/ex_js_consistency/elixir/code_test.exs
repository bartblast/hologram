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

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the argument is not an atom" do
      expected_msg =
        build_function_clause_error_msg("Code.ensure_compiled/1", [1], [
          "def ensure_compiled(module) when -is_atom(module)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn -> Code.ensure_compiled(1) end
    end
  end
end
