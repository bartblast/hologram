defmodule Hologram.FrameworkTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Framework
  alias Hologram.Reflection

  setup_all do
    [result: elixir_stdlib_erlang_deps()]
  end

  describe "elixir_stdlib_erlang_deps/0" do
    test "returns expected groups and modules", %{result: result} do
      assert is_map(result)

      # Check groups
      group_names = Map.keys(result)
      assert "Core" in group_names
      assert "Data Types" in group_names

      # Check Core group contains Kernel module
      core_group = Map.get(result, "Core")
      assert Map.has_key?(core_group, Kernel)

      # Check Data Types group contains expected modules
      data_types_group = Map.get(result, "Data Types")
      assert Map.has_key?(data_types_group, Atom)
      assert Map.has_key?(data_types_group, Base)
    end

    test "has correct three-level nested structure: groups -> modules -> functions -> Erlang MFAs",
         %{result: result} do
      # Level 1: Groups (string keys)
      assert is_map(result)

      Enum.each(result, fn {group_name, group_map} ->
        assert is_binary(group_name)

        # Level 2: Modules (atom keys)
        assert is_map(group_map)
        refute Enum.empty?(group_map)

        Enum.each(group_map, fn {module, module_map} ->
          assert is_atom(module)

          # Level 3: Functions ({name, arity} tuple keys)
          assert is_map(module_map)
          refute Enum.empty?(module_map)

          Enum.each(module_map, fn {function_key, erlang_mfas} ->
            # Function keys are {name, arity} tuples
            assert match?({fun, arity} when is_atom(fun) and is_integer(arity), function_key)
            {_fun, arity} = function_key
            assert arity >= 0

            # Values are lists of Erlang MFAs
            assert is_list(erlang_mfas)

            # Each Erlang MFA is a {module, fun, arity} tuple
            Enum.each(erlang_mfas, fn erlang_mfa ->
              assert match?(
                       {module, fun, arity}
                       when is_atom(module) and is_atom(fun) and is_integer(arity),
                       erlang_mfa
                     )
            end)
          end)
        end)
      end)
    end

    test "includes all public functions from each module", %{result: result} do
      # Verify for Atom and Base modules
      data_types_group = Map.get(result, "Data Types")

      for module <- [Atom, Base] do
        module_map = Map.get(data_types_group, module)
        expected_functions = module.__info__(:functions)

        assert Enum.count(expected_functions) > 0

        Enum.each(expected_functions, fn {fun, arity} ->
          assert Map.has_key?(module_map, {fun, arity}),
                 "Expected function #{fun}/#{arity} to be present in #{module} module map"

          erlang_mfas = Map.get(module_map, {fun, arity})
          assert is_list(erlang_mfas)
        end)
      end
    end

    test "all dependency MFAs are from Erlang modules only", %{result: result} do
      Enum.each(result, fn {_group_name, group_map} ->
        Enum.each(group_map, fn {_module, module_map} ->
          Enum.each(module_map, fn {_function_key, erlang_mfas} ->
            Enum.each(erlang_mfas, fn {module, _fun, _arity} ->
              assert Reflection.erlang_module?(module),
                     "Expected #{inspect(module)} to be an Erlang module"

              refute Reflection.elixir_module?(module),
                     "Expected #{inspect(module)} not to be an Elixir module"

              # Erlang modules start with lowercase letters
              module_str = Atom.to_string(module)
              first_char = String.first(module_str)

              assert first_char >= "a" and first_char <= "z",
                     "Expected Erlang module #{inspect(module)} to start with lowercase letter"
            end)
          end)
        end)
      end)
    end

    test "Kernel module has many functions", %{result: result} do
      core_group = Map.get(result, "Core")
      kernel_module_map = Map.get(core_group, Kernel)

      # Kernel is a large module with many functions
      assert Enum.count(kernel_module_map) > 50
    end
  end
end
