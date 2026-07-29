defmodule Hologram.ExJsConsistency.Erlang.ErlKernelErrorsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erl_kernel_errors_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @error_info [error_info: %{module: :erl_kernel_errors}]

  describe "format_error/2" do
    test "returns an empty map when the module has no formatter" do
      stacktrace = [{:some_module, :f, [1], @error_info}]

      assert :erl_kernel_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "returns an empty map for a function without a formatter clause" do
      stacktrace = [{:os, :type, [], @error_info}]

      assert :erl_kernel_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "returns an empty map when the frame carries an arity" do
      stacktrace = [{:os, :system_time, 1, @error_info}]

      assert :erl_kernel_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "os system_time: invalid time unit" do
      stacktrace = [{:os, :system_time, [:bad], @error_info}]

      assert :erl_kernel_errors.format_error(:badarg, stacktrace) == %{
               1 => "invalid time unit"
             }
    end

    test "raises FunctionClauseError when the stacktrace is empty" do
      stacktrace = []

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_kernel_errors.format_error/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_kernel_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when the top frame is not a 4-tuple" do
      stacktrace = [{:os}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_kernel_errors.format_error/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_kernel_errors, :format_error, [:badarg, stacktrace]}
    end
  end
end
