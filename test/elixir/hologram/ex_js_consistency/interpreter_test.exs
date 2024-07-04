defmodule Hologram.ExJsConsistency.InterpreterTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter.mjs.
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @env %Macro.Env{
    aliases: [{Module1, Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1}]
  }

  describe "call named function" do
    test "remote private function call" do
      assert_error UndefinedFunctionError,
                   "function Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1.my_private_fun/2 is undefined or private. Did you mean:\n\n      * my_public_fun/1\n      * my_public_fun/2\n",
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.my_private_fun(1, 2)", [], @env)
                   end
    end

    test "module is available, but function is undefined" do
      assert_error UndefinedFunctionError,
                   "function Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1.undefined_function/2 is undefined or private",
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.undefined_function(1, 2)", [], @env)
                   end
    end

    test "module is not available" do
      assert_error UndefinedFunctionError,
                   "function MyModule.my_fun/2 is undefined (module MyModule is not available)",
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("MyModule.my_fun(1, 2)", [], @env)
                   end
    end

    test "function with the same name and different arity is defined" do
      assert_error UndefinedFunctionError,
                   "function Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1.my_public_fun/3 is undefined or private. Did you mean:\n\n      * my_public_fun/1\n      * my_public_fun/2\n",
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.my_public_fun(1, 2, 3)", [], @env)
                   end
    end

    test "function arity is correct, but args don't match the pattern" do
      assert_error FunctionClauseError,
                   "no function clause matching in Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1.my_public_fun/2\n\nThe following arguments were given to Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1.my_public_fun/2:\n\n    # 1\n    1\n\n    # 2\n    3\n\nAttempted function clauses (showing 1 out of 1):\n\n    def my_public_fun(x, -2-)\n",
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.my_public_fun(1, 3)", [], @env)
                   end
    end
  end
end
