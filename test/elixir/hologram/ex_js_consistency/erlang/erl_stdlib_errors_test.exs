defmodule Hologram.ExJsConsistency.Erlang.ErlStdlibErrorsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erl_stdlib_errors_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @error_info [error_info: %{module: :erl_stdlib_errors}]

  describe "format_error/2" do
    test "returns an empty map when the module has no formatter" do
      stacktrace = [{:some_module, :f, [1], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "returns an empty map when the frame carries no error_info" do
      stacktrace = [{:some_module, :f, [1], []}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "consults only the first stacktrace frame" do
      stacktrace = [
        {:some_module, :f, [1], @error_info},
        {:maps, :get, [:a, :b], @error_info}
      ]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "raises FunctionClauseError when the stacktrace is empty" do
      stacktrace = []

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_error/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when the top frame is not a 4-tuple" do
      fun = fn -> :ok end
      stacktrace = [{fun, [1], @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_error/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end
  end
end
