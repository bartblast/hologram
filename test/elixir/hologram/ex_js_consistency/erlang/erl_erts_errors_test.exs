defmodule Hologram.ExJsConsistency.Erlang.ErlErtsErrorsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erl_erts_errors_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @error_info [error_info: %{module: :erl_erts_errors}]

  describe "format_error/2" do
    test "returns an empty map when the module has no formatter" do
      stacktrace = [{:some_module, :f, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "returns an empty map for a system_limit reason" do
      stacktrace = [{:erlang, :length, [:x], @error_info}]

      assert :erl_erts_errors.format_error(:system_limit, stacktrace) == %{}
    end

    test "returns an empty map for a function without a formatter clause" do
      stacktrace = [{:erlang, :++, [:x, []], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "erlang element: bad index" do
      stacktrace = [{:erlang, :element, [:x, {:a}], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an integer"}
    end

    test "erlang element: index out of range" do
      stacktrace = [{:erlang, :element, [0, {:a}], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "out of range"}
    end

    test "erlang element: index beyond the tuple size" do
      stacktrace = [{:erlang, :element, [5, {:a}], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "out of range"}
    end

    test "erlang element: not a tuple" do
      stacktrace = [{:erlang, :element, [1, :x], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{2 => "not a tuple"}
    end

    test "erlang element: bad index and not a tuple" do
      stacktrace = [{:erlang, :element, [:x, :y], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an integer",
               2 => "not a tuple"
             }
    end

    test "erlang is_map_key: not a map" do
      stacktrace = [{:erlang, :is_map_key, [:k, :x], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "erlang length: not a list" do
      stacktrace = [{:erlang, :length, [:x], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "erlang map_get: key not present in map" do
      stacktrace = [{:erlang, :map_get, [:k, %{}], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not present in map"}
    end

    test "erlang map_get: not a map" do
      stacktrace = [{:erlang, :map_get, [:k, :x], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "raises FunctionClauseError when the stacktrace is empty" do
      expected_msg =
        build_function_clause_error_msg(":erl_erts_errors.format_error/2", [:badarg, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :erl_erts_errors.format_error(:badarg, [])
      end
    end

    test "raises FunctionClauseError when the top frame is not a 4-tuple" do
      expected_msg =
        build_function_clause_error_msg(":erl_erts_errors.format_error/2", [:badarg, [{:erlang}]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :erl_erts_errors.format_error(:badarg, [{:erlang}])
      end
    end
  end
end
