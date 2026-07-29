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

    test "maps find: not a map" do
      stacktrace = [{:maps, :find, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps fold: bad fun and bad collection" do
      stacktrace = [{:maps, :fold, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes three arguments",
               3 => "not a map or an iterator"
             }
    end

    test "maps fold: valid fun and iterator skip their fragments" do
      fun = fn acc, _key, _value -> acc end
      stacktrace = [{:maps, :fold, [fun, :b, [0 | %{a: 1}]], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{}
    end

    test "maps fold: iterator validity is checked recursively" do
      fun = fn acc, _key, _value -> acc end
      stacktrace = [{:maps, :fold, [fun, :b, {1, 2, 3}], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               3 => "not a map or an iterator"
             }
    end

    test "maps from_keys: improper list" do
      stacktrace = [{:maps, :from_keys, [[1 | 2], :a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a proper list"}
    end

    test "maps from_list: not a list" do
      stacktrace = [{:maps, :from_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "maps get/2: key not present in map" do
      stacktrace = [{:maps, :get, [:a, %{b: 2}], @error_info}]

      assert :erl_stdlib_errors.format_error(:badkey, stacktrace) == %{1 => "not present in map"}
    end

    test "maps get/2: not a map" do
      stacktrace = [{:maps, :get, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps get/3: not a map" do
      stacktrace = [{:maps, :get, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps intersect: both arguments not maps" do
      stacktrace = [{:maps, :intersect, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a map",
               2 => "not a map"
             }
    end

    test "maps intersect_with: bad fun and bad maps" do
      stacktrace = [{:maps, :intersect_with, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes three arguments",
               2 => "not a map",
               3 => "not a map"
             }
    end

    test "maps is_key: not a map" do
      stacktrace = [{:maps, :is_key, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps iterator: not a map" do
      stacktrace = [{:maps, :iterator, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a map"}
    end

    test "maps keys: not a map" do
      stacktrace = [{:maps, :keys, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a map"}
    end

    test "maps map: bad fun and bad collection" do
      stacktrace = [{:maps, :map, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes two arguments",
               2 => "not a map or an iterator"
             }
    end

    test "maps merge: both arguments not maps" do
      stacktrace = [{:maps, :merge, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a map",
               2 => "not a map"
             }
    end

    test "maps merge_with: bad fun and bad maps" do
      stacktrace = [{:maps, :merge_with, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a fun that takes three arguments",
               2 => "not a map",
               3 => "not a map"
             }
    end

    test "maps next: bad iterator" do
      stacktrace = [{:maps, :next, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a valid iterator"
             }
    end

    test "maps put: not a map" do
      stacktrace = [{:maps, :put, [:a, :b, :c], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "not a map"}
    end

    test "maps remove: not a map" do
      stacktrace = [{:maps, :remove, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps take: not a map" do
      stacktrace = [{:maps, :take, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a map"}
    end

    test "maps to_list: not a map or iterator" do
      stacktrace = [{:maps, :to_list, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a map or an iterator"
             }
    end

    test "maps update: key not present in map" do
      stacktrace = [{:maps, :update, [:a, 1, %{b: 2}], @error_info}]

      assert :erl_stdlib_errors.format_error(:badkey, stacktrace) == %{
               1 => "not present in map"
             }
    end

    test "maps update: not a map" do
      stacktrace = [{:maps, :update, [:a, 1, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{3 => "not a map"}
    end

    test "maps values: not a map" do
      stacktrace = [{:maps, :values, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a map"}
    end

    test "math ceil: not a number" do
      stacktrace = [{:math, :ceil, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "math log: domain error" do
      stacktrace = [{:math, :log, [0], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "is outside the domain for this function"
             }
    end

    test "math log: not a number" do
      stacktrace = [{:math, :log, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "math pow: both arguments not numbers" do
      stacktrace = [{:math, :pow, [:a, :b], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a number",
               2 => "not a number"
             }
    end

    test "math pow: valid number skips its fragment" do
      stacktrace = [{:math, :pow, [7, :a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{2 => "not a number"}
    end

    test "math unknown functions fall to the argument-count clauses" do
      stacktrace = [{:math, :unknown, [:a], @error_info}]

      assert :erl_stdlib_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
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

    test "raises FunctionClauseError when a maps clause needs args but the frame carries an arity" do
      stacktrace = [{:maps, :get, 2, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_maps_error/2", [
                     :get,
                     2
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a math clause needs args but the frame carries an arity" do
      stacktrace = [{:math, :ceil, 1, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.format_math_error/2", [
                     :ceil,
                     1
                   ]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end

    test "raises FunctionClauseError when a math domain-error clause needs args but the frame carries an arity" do
      stacktrace = [{:math, :log, 1, @error_info}]

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_stdlib_errors.maybe_domain_error/1", [1]),
                   {:erl_stdlib_errors, :format_error, [:badarg, stacktrace]}
    end
  end
end
