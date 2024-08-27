defmodule Hologram.ExJsConsistency.InterpreterTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter.mjs.
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1

  @moduletag :consistency

  @env %Macro.Env{
    aliases: [{:"Elixir.Module1", Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1}]
  }

  describe "call anonymous function" do
    # TODO: client error message for this case is inconsistent with server error message (see test/javascript/interpreter_test.mjs)
    test "arity is invalid, called with no args" do
      fun = fn
        1 -> :expr_1
        2 -> :expr_2
      end

      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/1 in Hologram.ExJsConsistency\.InterpreterTest\."test call anonymous function arity is invalid, called with no args"/1> with arity 1 called with no arguments'

      assert_error BadArityError, expected_msg, fn -> fun.() end
    end

    # TODO: client error message for this case is inconsistent with server error message (see test/javascript/interpreter_test.mjs)
    test "arity is invalid, called with a single arg" do
      fun = fn
        1, 2 -> :expr_1
        3, 4 -> :expr_2
      end

      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/2 in Hologram.ExJsConsistency\.InterpreterTest\."test call anonymous function arity is invalid, called with a single arg"/1> with arity 2 called with 1 argument \(9\)'

      assert_error BadArityError, expected_msg, fn -> fun.(9) end
    end

    # TODO: client error message for this case is inconsistent with server error message (see test/javascript/interpreter_test.mjs)
    test "arity is invalid, called with multiple args" do
      fun = fn
        1 -> :expr_1
        2 -> :expr_2
      end

      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/1 in Hologram.ExJsConsistency\.InterpreterTest\."test call anonymous function arity is invalid, called with multiple args"/1> with arity 1 called with 2 arguments \(9, 8\)'

      assert_error BadArityError, expected_msg, fn -> fun.(9, 8) end
    end

    # TODO: client error message for this case is inconsistent with server error message (see test/javascript/interpreter_test.mjs)
    test "arity is valid, but args don't match the pattern in any of the clauses" do
      fun = fn
        1 -> :expr_1
        2 -> :expr_2
      end

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(
                     ~s(anonymous fn/1 in Hologram.ExJsConsistency.InterpreterTest."test call anonymous function arity is valid, but args don't match the pattern in any of the clauses"/1),
                     [9]
                   ),
                   fn -> fun.(9) end
    end
  end

  describe "call named function" do
    test "remote private function call" do
      expected_msg =
        build_undefined_function_error({Module1, :my_private_fun, 2}, [
          {:my_public_fun, 1},
          {:my_public_fun, 2}
        ])

      assert_error UndefinedFunctionError,
                   expected_msg,
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.my_private_fun(1, 2)", [], @env)
                   end
    end

    test "module is available, but function is undefined" do
      expected_msg = build_undefined_function_error({Module1, :undefined_function, 2})

      assert_error UndefinedFunctionError,
                   expected_msg,
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.undefined_function(1, 2)", [], @env)
                   end
    end

    test "module is not available" do
      expected_msg = build_undefined_function_error({MyModule, :my_fun, 2}, [], false)

      assert_error UndefinedFunctionError,
                   expected_msg,
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("MyModule.my_fun(1, 2)", [], @env)
                   end
    end

    test "function with the same name and different arity is defined" do
      expected_msg =
        build_undefined_function_error({Module1, :my_public_fun, 3}, [
          {:my_public_fun, 1},
          {:my_public_fun, 2}
        ])

      assert_error UndefinedFunctionError,
                   expected_msg,
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.my_public_fun(1, 2, 3)", [], @env)
                   end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "function arity is correct, but args don't match the pattern" do
      expected_msg =
        build_function_clause_error_msg(
          "Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1.my_public_fun/2",
          [1, 3],
          ["def my_public_fun(x, -2-)"]
        )

      assert_error FunctionClauseError, expected_msg, fn ->
        Code.eval_string("Module1.my_public_fun(1, 3)", [], @env)
      end
    end
  end
end
