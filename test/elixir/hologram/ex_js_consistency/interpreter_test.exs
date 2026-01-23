defmodule Hologram.ExJsConsistency.InterpreterTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related unit JavaScript or Elixir feature test.
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1

  @moduletag :consistency

  @env %Macro.Env{
    aliases: [{:"Elixir.Module1", Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1}]
  }

  @spec my_local_fun(integer, integer) :: integer
  def my_local_fun(x, y) do
    x + y * x
  end

  # IMPORTANT!
  # Keep consistent with feature tests in test/features/test/function_calls/anonymous_function_test.exs
  # TODO: reimplement to be consistent with feature tests in test/features/test/function_calls/anonymous_function_test.exs
  describe "call anonymous function" do
    # TODO: client error message for this case is inconsistent with server error message
    test "arity is invalid, called with no args" do
      fun = fn
        1 -> :expr_1
        2 -> :expr_2
      end

      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/1 in Hologram.ExJsConsistency\.InterpreterTest\."test call anonymous function arity is invalid, called with no args"/1> with arity 1 called with no arguments'

      assert_error BadArityError, expected_msg, fn -> fun.() end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "arity is invalid, called with a single arg" do
      fun = fn
        1, 2 -> :expr_1
        3, 4 -> :expr_2
      end

      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/2 in Hologram.ExJsConsistency\.InterpreterTest\."test call anonymous function arity is invalid, called with a single arg"/1> with arity 2 called with 1 argument \(9\)'

      assert_error BadArityError, expected_msg, fn -> fun.(9) end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "arity is invalid, called with multiple args" do
      fun = fn
        1 -> :expr_1
        2 -> :expr_2
      end

      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/1 in Hologram.ExJsConsistency\.InterpreterTest\."test call anonymous function arity is invalid, called with multiple args"/1> with arity 1 called with 2 arguments \(9, 8\)'

      assert_error BadArityError, expected_msg, fn -> fun.(9, 8) end
    end

    # credo:disable-for-lines:15 Credo.Check.Readability.MaxLineLength
    # TODO: fix the failing test (except the error message inconsistency):
    # TODO: client error message for this case is inconsistent with server error message
    # test "no matching clause" do
    #   fun = fn
    #     1 -> :expr_1
    #     2 -> :expr_2
    #   end

    #   assert_error FunctionClauseError,
    #                build_function_clause_error_msg(
    #                  ~s(anonymous fn/1 in Hologram.ExJsConsistency.InterpreterTest."test call anonymous function arity is valid, but args don't match the pattern in any of the clauses"/1),
    #                  [9]
    #                ),
    #                fn -> fun.(9) end
    # end
  end

  # IMPORTANT!
  # Keep consistent with feature tests in test/features/test/function_calls/function_capture_test.exs
  # TODO: implement
  # describe "call function capture"

  # IMPORTANT!
  # Keep consistent with feature tests in:
  # * test/features/test/function_calls/local_function_test.exs
  # * test/features/test/function_calls/remote_function_test.exs
  # TODO: split into "call local function" and "call remote function"
  # TODO: reimplement to be consistent with aforementioned feature tests
  describe "call named function" do
    test "remote private function call" do
      expected_msg =
        build_undefined_function_error_msg({Module1, :my_private_fun, 2}, [
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
      expected_msg = build_undefined_function_error_msg({Module1, :undefined_function, 2})

      assert_error UndefinedFunctionError,
                   expected_msg,
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("Module1.undefined_function(1, 2)", [], @env)
                   end
    end

    test "module is not available" do
      expected_msg = build_undefined_function_error_msg({MyModule, :my_fun, 2}, [], false)

      assert_error UndefinedFunctionError,
                   expected_msg,
                   fn ->
                     # Code.eval_string/3 used here, because this code wouldn't compile.
                     Code.eval_string("MyModule.my_fun(1, 2)", [], @env)
                   end
    end

    test "function with the same name and different arity is defined" do
      expected_msg =
        build_undefined_function_error_msg({Module1, :my_public_fun, 3}, [
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

  describe "inspect" do
    # Client result for non-capture anonymous function is intentionally different than server result.
    test "anonymous function, non-capture" do
      anon_fun = fn x, y -> x + y * x end

      Kernel.inspect(anon_fun, []) =~
        ~r'#Function<[0-9]+\.[0-9]/2 in Hologram\.ExJsConsistency\.InterpreterTest\."test inspect/2 anonymous function, non-capture"/1>'
    end

    test "anonymous function, local function capture" do
      assert Kernel.inspect(&my_local_fun/2, []) =~
               ~r'^#Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.InterpreterTest\.my_local_fun>$'
    end

    test "anonymous function, remote function capture" do
      assert Kernel.inspect(&DateTime.now/2) == "&DateTime.now/2"
    end

    test "atom, true" do
      assert Kernel.inspect(true, []) == "true"
    end

    test "atom, false" do
      assert Kernel.inspect(false, []) == "false"
    end

    test "atom, nil" do
      assert Kernel.inspect(nil, []) == "nil"
    end

    test "atom, module alias" do
      assert Kernel.inspect(Aaa.Bbb, []) == "Aaa.Bbb"
    end

    test "atom, non-boolean and non-nil" do
      assert Kernel.inspect(:abc, []) == ":abc"
    end

    test "bitstring, text, empty" do
      assert Kernel.inspect("", []) == ~s'""'
    end

    test "bitstring, text, ASCII" do
      assert Kernel.inspect("abc", []) == ~s'"abc"'
    end

    test "bitstring, text, Unicode" do
      assert Kernel.inspect("全息图", []) == ~s'"全息图"'
    end

    test "bitstring, text, non-printable" do
      assert Kernel.inspect("a\x01b") == "<<97, 1, 98>>"
    end

    # TODO: bitstring / bytes (see client-side Interpreter.inspect() tests)

    test "float, integer-representable" do
      assert Kernel.inspect(123.0, []) == "123.0"
    end

    test "float, not integer-representable" do
      assert Kernel.inspect(123.45, []) == "123.45"
    end

    test "integer" do
      assert Kernel.inspect(123, []) == "123"
    end

    test "list, empty" do
      assert Kernel.inspect([], []) == "[]"
    end

    test "list, proper" do
      assert Kernel.inspect([1, 2, 3], []) == "[1, 2, 3]"
    end

    test "list, improper" do
      assert Kernel.inspect([1, 2 | 3], []) == "[1, 2 | 3]"
    end

    # TODO: lits / keyword list (see client-side Interpreter.inspect() tests)

    test "map, empty" do
      assert Kernel.inspect(%{}, []) == "%{}"
    end

    test "map, with atom keys" do
      assert Kernel.inspect(%{a: 1, b: "xyz"}, []) in [
               ~s'%{a: 1, b: "xyz"}',
               ~s'%{b: "xyz", a: 1}'
             ]
    end

    test "map, with non-atom keys" do
      assert Kernel.inspect(%{9 => "xyz", "abc" => 2.3}, []) == ~s'%{9 => "xyz", "abc" => 2.3}'
    end

    # TODO: maps / sort_maps opt (see client-side Interpreter.inspect() tests)

    # TODO: maps / structs

    assert "PID" do
      result =
        "0.11.222"
        |> pid()
        |> Kernel.inspect()

      assert result == "#PID<0.11.222>"
    end

    assert "port" do
      result =
        "0.11"
        |> port()
        |> Kernel.inspect()

      assert result == "#Port<0.11>"
    end

    assert "reference" do
      result =
        "0.1.2.3"
        |> ref()
        |> Kernel.inspect()

      assert result == "#Reference<0.1.2.3>"
    end

    test "tuple, empty" do
      assert Kernel.inspect({}, []) == "{}"
    end

    test "tuple, non-empty" do
      assert Kernel.inspect({1, 2, 3}, []) == "{1, 2, 3}"
    end
  end
end
