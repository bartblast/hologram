defmodule Hologram.ExJsConsistency.Erlang.ErlErtsErrorsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erl_erts_errors_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @error_info [error_info: %{module: :erl_erts_errors}]

  defp bs_stacktrace(error_info_map) do
    [{:m, :f, 1, [error_info: error_info_map]}]
  end

  defp expected_bs_result(general) do
    %{general: general, reason: "construction of binary failed"}
  end

  describe "format_bs_fail/2" do
    test "returns an empty map when the error_info carries no cause" do
      stacktrace = bs_stacktrace(%{module: :erl_erts_errors})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) == %{}
    end

    test "returns an empty map when the frame carries no error_info" do
      stacktrace = [{:m, :f, 1, []}]

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) == %{}
    end

    test "formats an integer type mismatch" do
      stacktrace = bs_stacktrace(%{cause: {1, :integer, :type, 1.5}})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result("segment 1 of type 'integer': expected an integer but got: 1.5")
    end

    test "formats a binary type mismatch" do
      stacktrace = bs_stacktrace(%{cause: {1, :binary, :type, 5}})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result("segment 1 of type 'binary': expected a binary but got: 5")
    end

    test "formats a utf type mismatch" do
      stacktrace = bs_stacktrace(%{cause: {2, :utf8, :type, 5}})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result(
                 "segment 2 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 5"
               )
    end

    test "formats an invalid float size" do
      stacktrace = bs_stacktrace(%{cause: {1, :float, :invalid, 8}})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result(
                 "segment 1 of type 'float': expected one of the supported sizes 16, 32, or 64 but got: 8"
               )
    end

    test "formats a short value" do
      stacktrace = bs_stacktrace(%{cause: {1, :integer, :short, 5}})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result(
                 "segment 1 of type 'integer': the value 5 is shorter than the size of the segment"
               )
    end

    test "formats an invalid size" do
      stacktrace = bs_stacktrace(%{cause: {1, :integer, :size, -1}})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result(
                 "segment 1 of type 'integer': expected a non-negative integer as size but got: -1"
               )
    end

    test "honors the override_segment_position" do
      stacktrace =
        bs_stacktrace(%{cause: {1, :integer, :type, 5}, override_segment_position: 3})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result("segment 3 of type 'integer': expected an integer but got: 5")
    end

    test "applies the error_info pretty printer" do
      stacktrace =
        bs_stacktrace(%{cause: {1, :binary, :unit, <<1::size(3)>>}, pretty_printer: &inspect/1})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result(
                 "segment 1 of type 'binary': the size of the value <<1::size(3)>> is not a multiple of the unit for the segment"
               )
    end

    test "formats a float outside the expressible range with the pretty printer" do
      stacktrace =
        bs_stacktrace(%{cause: {1, :float, :no_float, :abc}, pretty_printer: &inspect/1})

      assert :erl_erts_errors.format_bs_fail(:badarg, stacktrace) ==
               expected_bs_result(
                 "segment 1 of type 'float': the value :abc is outside the range expressible as a float"
               )
    end

    test "formats a too large size for a system_limit reason" do
      stacktrace = bs_stacktrace(%{cause: {1, :integer, :size, 99}})

      assert :erl_erts_errors.format_bs_fail(:system_limit, stacktrace) ==
               expected_bs_result("segment 1 of type 'integer': the size 99 is too large")
    end

    test "formats a too large binary for a system_limit reason" do
      stacktrace = bs_stacktrace(%{cause: {1, :binary, :binary, :size}})

      assert :erl_erts_errors.format_bs_fail(:system_limit, stacktrace) ==
               expected_bs_result(
                 "segment 1 of type 'binary': the size of the binary/bitstring is too large (exceeding 2147483647 bits)"
               )
    end

    test "raises FunctionClauseError when the stacktrace is empty" do
      stacktrace = []

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":erl_erts_errors.format_bs_fail/2", [
                     :badarg,
                     stacktrace
                   ]),
                   {:erl_erts_errors, :format_bs_fail, [:badarg, stacktrace]}
    end
  end

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

    test "erlang abs: not a number" do
      stacktrace = [{:erlang, :abs, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "erlang append_element: not a tuple" do
      stacktrace = [{:erlang, :append_element, [:a, :b], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a tuple"}
    end

    test "erlang apply: bad module and args" do
      stacktrace = [{:erlang, :apply, [1, :f, :bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an atom",
               3 => "not a list"
             }
    end

    test "erlang binary_part: bad positions" do
      stacktrace = [{:erlang, :binary_part, ["abc", :a, :b], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               2 => "not an integer",
               3 => "not an integer"
             }
    end

    test "erlang binary_part: start out of range" do
      stacktrace = [{:erlang, :binary_part, ["abc", 5, 1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{2 => "out of range"}
    end

    test "erlang binary_part: length out of range" do
      stacktrace = [{:erlang, :binary_part, ["abc", 1, 5], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{3 => "out of range"}
    end

    test "erlang convert_time_unit: bad time and unit" do
      stacktrace = [{:erlang, :convert_time_unit, [:a, :second, :bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an integer",
               3 => "invalid time unit"
             }
    end

    test "erlang delete_element delegates to the element clause" do
      stacktrace = [{:erlang, :delete_element, [:a, :b], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an integer",
               2 => "not a tuple"
             }
    end

    test "erlang float: not a number" do
      stacktrace = [{:erlang, :float, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "erlang fun_info: not a fun" do
      stacktrace = [{:erlang, :fun_info, [1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a fun"}
    end

    test "erlang function_exported: bad args" do
      stacktrace = [{:erlang, :function_exported, [1, 2, :a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an atom",
               2 => "not an atom",
               3 => "not an integer"
             }
    end

    test "erlang hd: not a nonempty list" do
      stacktrace = [{:erlang, :hd, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a nonempty list"}
    end

    test "erlang insert_element delegates to the element clause" do
      stacktrace = [{:erlang, :insert_element, [:a, :b, :c], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an integer",
               2 => "not a tuple"
             }
    end

    test "erlang iolist_to_binary: not an iodata term" do
      stacktrace = [{:erlang, :iolist_to_binary, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not an iodata term"}
    end

    test "erlang make_fun: bad args" do
      stacktrace = [{:erlang, :make_fun, [1, 2, -1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not an atom",
               2 => "not an atom",
               3 => "out of range"
             }
    end

    test "erlang make_tuple/2: bad arity" do
      stacktrace = [{:erlang, :make_tuple, [:a, :b], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "out of range"}
    end

    test "erlang monotonic_time: invalid time unit" do
      stacktrace = [{:erlang, :monotonic_time, [:bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "invalid time unit"}
    end

    test "erlang pid_to_list: not a pid" do
      stacktrace = [{:erlang, :pid_to_list, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a pid"}
    end

    test "erlang ref_to_list: not a reference" do
      stacktrace = [{:erlang, :ref_to_list, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a reference"}
    end

    test "erlang round: not a number" do
      stacktrace = [{:erlang, :round, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "erlang setelement delegates to the element clause" do
      stacktrace = [{:erlang, :setelement, [0, {:a}, :x], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "out of range"}
    end

    test "erlang split_binary: bad args" do
      stacktrace = [{:erlang, :split_binary, [:a, -1], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "not a binary",
               2 => "out of range"
             }
    end

    test "erlang split_binary: position out of range" do
      stacktrace = [{:erlang, :split_binary, ["abc", 5], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{2 => "out of range"}
    end

    test "erlang system_info: invalid item" do
      stacktrace = [{:erlang, :system_info, [:bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{
               1 => "invalid system info item"
             }
    end

    test "erlang system_time: invalid time unit" do
      stacktrace = [{:erlang, :system_time, [:bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "invalid time unit"}
    end

    test "erlang time_offset: invalid time unit" do
      stacktrace = [{:erlang, :time_offset, [:bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "invalid time unit"}
    end

    test "erlang tl: not a nonempty list" do
      stacktrace = [{:erlang, :tl, [[]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a nonempty list"}
    end

    test "erlang trunc: not a number" do
      stacktrace = [{:erlang, :trunc, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a number"}
    end

    test "erlang tuple_size: not a tuple" do
      stacktrace = [{:erlang, :tuple_size, [:a], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a tuple"}
    end

    test "erlang unique_integer: not a list" do
      stacktrace = [{:erlang, :unique_integer, [:bad], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "not a list"}
    end

    test "erlang unique_integer: invalid modifier" do
      stacktrace = [{:erlang, :unique_integer, [[:bad]], @error_info}]

      assert :erl_erts_errors.format_error(:badarg, stacktrace) == %{1 => "invalid modifier"}
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

    test "error frame carries args" do
      stacktrace = wrap_term([])

      top_frame =
        try do
          :erl_erts_errors.format_error(:badarg, stacktrace)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Erlang code inside erl_erts_errors.erl,
      # so its frame location also carries the corresponding file and line,
      # which the client doesn't mirror.
      assert {module, function, args, location} = top_frame

      assert {module, function, args} == {:erl_erts_errors, :format_error, [:badarg, []]}
      assert location[:error_info] == nil
    end
  end
end
