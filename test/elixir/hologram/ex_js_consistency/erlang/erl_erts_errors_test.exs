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

    test "erlang atom_to_binary/1: not an atom" do
      stacktrace = [{:erlang, :atom_to_binary, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an atom"}
    end

    test "erlang atom_to_binary/2: not an atom" do
      stacktrace = [{:erlang, :atom_to_binary, [1, :utf8], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an atom"}
    end

    test "erlang atom_to_binary/2: latin1-inexpressible atom" do
      stacktrace = [{:erlang, :atom_to_binary, [:hologram, :latin1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "contains a character not expressible in latin1"
             }
    end

    test "erlang atom_to_binary/2: invalid encoding" do
      stacktrace = [{:erlang, :atom_to_binary, [:a, :bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "is an invalid encoding option"
             }
    end

    test "erlang atom_to_list: not an atom" do
      stacktrace = [{:erlang, :atom_to_list, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an atom"}
    end

    test "erlang binary_to_atom/1: not a binary" do
      stacktrace = [{:erlang, :binary_to_atom, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a binary"}
    end

    test "erlang binary_to_atom/1: invalid UTF-8" do
      stacktrace = [{:erlang, :binary_to_atom, [<<255>>], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "invalid UTF8 encoding"}
    end

    test "erlang binary_to_atom/2: invalid encoding" do
      stacktrace = [{:erlang, :binary_to_atom, ["a", :bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "not one of the atoms: latin1, utf8, or unicode"
             }
    end

    test "erlang binary_to_atom/2: latin1 with a non-binary" do
      stacktrace = [{:erlang, :binary_to_atom, [1, :latin1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a binary"}
    end

    test "erlang binary_to_existing_atom/1: valid binary" do
      stacktrace = [{:erlang, :binary_to_existing_atom, ["nonexistent"], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an already existing atom"
             }
    end

    test "erlang binary_to_float: not a binary" do
      stacktrace = [{:erlang, :binary_to_float, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a binary"}
    end

    test "erlang binary_to_float: bad content" do
      stacktrace = [{:erlang, :binary_to_float, ["abc"], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => ["not a textual representation of ", "a float"]
             }
    end

    test "erlang binary_to_integer/1: bad content" do
      stacktrace = [{:erlang, :binary_to_integer, ["abc"], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => ["not a textual representation of ", "an integer"]
             }
    end

    test "erlang binary_to_integer/2: bad base" do
      stacktrace = [{:erlang, :binary_to_integer, ["abc", 50], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "not an integer in the range 2 through 36"
             }
    end

    test "erlang binary_to_integer/2: not a binary and bad base" do
      stacktrace = [{:erlang, :binary_to_integer, [1, 50], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a binary",
               2 => "not an integer in the range 2 through 36"
             }
    end

    test "erlang binary_to_list: not a binary" do
      stacktrace = [{:erlang, :binary_to_list, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a binary"}
    end

    test "erlang binary_to_term: bad content" do
      stacktrace = [{:erlang, :binary_to_term, ["abc"], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "invalid external representation of a term"
             }
    end

    test "erlang binary_to_term: not a binary" do
      stacktrace = [{:erlang, :binary_to_term, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a binary"}
    end

    test "erlang bit_size: not a bitstring" do
      stacktrace = [{:erlang, :bit_size, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a bitstring"}
    end

    test "erlang byte_size: not a bitstring" do
      stacktrace = [{:erlang, :byte_size, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a bitstring"}
    end

    test "erlang ceil: not a number" do
      stacktrace = [{:erlang, :ceil, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "erlang floor: not a number" do
      stacktrace = [{:erlang, :floor, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "erlang float_to_binary/1: not a float" do
      stacktrace = [{:erlang, :float_to_binary, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a float"}
    end

    test "erlang float_to_binary/2: bad option" do
      stacktrace = [{:erlang, :float_to_binary, [1.0, [:bad]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "invalid option in list"
             }
    end

    test "erlang float_to_binary/2: not a float" do
      stacktrace = [{:erlang, :float_to_binary, [1, [:bad]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a float"}
    end

    test "erlang float_to_binary/2: improper options" do
      stacktrace = [{:erlang, :float_to_binary, [1.0, [:a | :b]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{2 => "not a proper list"}
    end

    test "erlang float_to_list/1: not a float" do
      stacktrace = [{:erlang, :float_to_list, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a float"}
    end

    test "erlang integer_to_binary/1: not an integer" do
      stacktrace = [{:erlang, :integer_to_binary, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an integer"}
    end

    test "erlang integer_to_binary/2: bad base" do
      stacktrace = [{:erlang, :integer_to_binary, [1, 50], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "not an integer in the range 2 through 36"
             }
    end

    test "erlang integer_to_list/1: not an integer" do
      stacktrace = [{:erlang, :integer_to_list, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an integer"}
    end

    test "erlang integer_to_list/2: not an integer and bad base" do
      stacktrace = [{:erlang, :integer_to_list, [:a, 50], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an integer",
               2 => "not an integer in the range 2 through 36"
             }
    end

    test "erlang list_to_atom: not a list" do
      stacktrace = [{:erlang, :list_to_atom, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "erlang list_to_atom: improper list" do
      stacktrace = [{:erlang, :list_to_atom, [[97 | 98]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a proper list"}
    end

    test "erlang list_to_atom: bad content" do
      stacktrace = [{:erlang, :list_to_atom, [[:a]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a list of characters"
             }
    end

    test "erlang list_to_binary: not an iolist" do
      stacktrace = [{:erlang, :list_to_binary, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an iolist term"}
    end

    test "erlang list_to_existing_atom: flat char list" do
      stacktrace = [{:erlang, :list_to_existing_atom, [[104, 105]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an already existing atom"
             }
    end

    test "erlang list_to_existing_atom: bad content" do
      stacktrace = [{:erlang, :list_to_existing_atom, [[:a]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a list of characters"
             }
    end

    test "erlang list_to_float: bad content" do
      stacktrace = [{:erlang, :list_to_float, [[97]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => ["not a textual representation of ", "a float"]
             }
    end

    test "erlang list_to_float: not a list" do
      stacktrace = [{:erlang, :list_to_float, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "erlang list_to_float: improper list" do
      stacktrace = [{:erlang, :list_to_float, [[97 | 98]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "erlang list_to_integer/1: bad content" do
      stacktrace = [{:erlang, :list_to_integer, [[97]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => ["not a textual representation of ", "an integer"]
             }
    end

    test "erlang list_to_integer/2: bad base" do
      stacktrace = [{:erlang, :list_to_integer, [[97], 50], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "not an integer in the range 2 through 36"
             }
    end

    test "erlang list_to_integer/2: not a list and bad base" do
      stacktrace = [{:erlang, :list_to_integer, [:a, 50], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a list",
               2 => "not an integer in the range 2 through 36"
             }
    end

    test "erlang list_to_pid: bad content" do
      stacktrace = [{:erlang, :list_to_pid, [[97]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => ["not a textual representation of ", "a pid"]
             }
    end

    test "erlang list_to_ref: bad content" do
      stacktrace = [{:erlang, :list_to_ref, [[97]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => ["not a textual representation of ", "a reference"]
             }
    end

    test "erlang list_to_tuple: not a list" do
      stacktrace = [{:erlang, :list_to_tuple, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "erlang tuple_to_list: not a tuple" do
      stacktrace = [{:erlang, :tuple_to_list, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a tuple"}
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
