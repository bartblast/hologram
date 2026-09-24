defmodule Hologram.Compiler.ReflectionSitesTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ReflectionSites

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.ReflectionSites.Module1
  alias Hologram.Test.Fixtures.Compiler.ReflectionSites.Module2
  alias Hologram.Test.Fixtures.Compiler.ReflectionSites.Module3

  @target {Module3, :target, 2}

  # The kinds of the arguments of each call of Module3.target/2 in the given function of Module3.
  defp call_arg_kinds(function) do
    function
    |> clause(Module3)
    |> call_args(Module3, @target)
    |> Enum.map(fn args -> Enum.map(args, &elem(&1, 0)) end)
  end

  defp clause(function, module \\ Module1) do
    %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}} = IR.for_module(module)

    Enum.find_value(expressions, fn
      %IR.FunctionDefinition{name: ^function, clause: clause} -> clause
      _expression -> nil
    end)
  end

  describe "call_args/3" do
    test "apply/3 with the module, the function and the argument list written out" do
      assert call_arg_kinds(:apply_call) == [[{:param, 0}, :other]]
    end

    test "call in an anonymous function" do
      assert call_arg_kinds(:call_in_anonymous_function) == [[{:param, 0}, :other]]
    end

    test "call of another function" do
      assert call_arg_kinds(:call_of_other_function) == []
    end

    test "call on a rebound param" do
      assert call_arg_kinds(:call_on_rebound_param) == [[:other, :other]]
    end

    test "call with a state value" do
      assert call_arg_kinds(:call_with_state_value) == [[:other, :other]]
    end

    test "calls repeated, in the order written" do
      assert call_arg_kinds(:calls_repeated) == [[{:param, 0}, :other], [:literal, :other]]
    end

    test "local call" do
      assert call_arg_kinds(:local_call) == [[{:param, 0}, :other]]
    end

    test "remote call, with each argument's IR" do
      assert [[{:literal, literal_ir}, {{:param, 0}, param_ir}]] =
               :remote_call
               |> clause(Module3)
               |> call_args(Module3, @target)

      assert literal_ir == %IR.AtomType{value: Module2}
      assert %IR.Variable{name: :fields} = param_ir
    end

    test "a local call is not a call of another module's function of the same name" do
      assert :local_call
             |> clause(Module3)
             |> call_args(Module3, {Module1, :target, 2}) == []
    end
  end

  test "functions/0" do
    assert functions() == [
             {:__changeset__, 0},
             {:__schema__, 1},
             {:__schema__, 2},
             {:__struct__, 0},
             {:__struct__, 1}
           ]
  end

  describe "list/1" do
    test "apply/3 with a function name and an argument list written out" do
      assert list(clause(:apply_with_function_name)) == [{:__schema__, 1, {:param, 0}}]
    end

    test "apply/3 with a function name and a variable argument list" do
      assert list(clause(:apply_with_function_name_and_variable_args)) == [
               {:__schema__, 1, {:param, 0}},
               {:__schema__, 2, {:param, 0}}
             ]
    end

    test "apply/3 with a variable function name" do
      assert list(clause(:apply_with_variable_function_name)) == []
    end

    test "call in an anonymous function" do
      assert list(clause(:call_in_anonymous_function)) == [{:__changeset__, 0, {:param, 0}}]
    end

    test "call of another function on a variable" do
      assert list(clause(:call_of_other_function)) == []
    end

    test "call on a literal module" do
      assert list(clause(:call_on_literal_module)) == []
    end

    test "call on a param" do
      assert list(clause(:call_on_param)) == [{:__changeset__, 0, {:param, 1}}]
    end

    test "call on a rebound param" do
      assert list(clause(:call_on_rebound_param)) == [{:__changeset__, 0, :open}]
    end

    test "call on a state value" do
      assert list(clause(:call_on_state_value)) == [{:__changeset__, 0, :open}]
    end

    test "call on a variable in IR built from a code string" do
      clause =
        "fn module -> module.__changeset__() end"
        |> IR.for_code(%Context{module: Module1})
        |> Map.fetch!(:clauses)
        |> hd()

      assert list(clause) == [{:__changeset__, 0, :open}]
    end

    test "calls repeated" do
      assert list(clause(:calls_repeated)) == [{:__changeset__, 0, {:param, 0}}]
    end

    test "dot on a param" do
      assert list(clause(:dot_on_param)) == [{:__struct__, 0, {:param, 0}}]
    end

    test "dot with the name of a reflection function that has no zero arity" do
      assert list(clause(:dot_with_schema_name)) == []
    end

    test "make_fun/3 with a variable function name" do
      assert list(clause(:make_fun_with_variable_function_name)) == []
    end

    test "no calls" do
      assert list(clause(:no_calls)) == []
    end

    test "__schema__/2 call" do
      assert list(clause(:schema_call_with_2_args)) == [{:__schema__, 2, {:param, 0}}]
    end

    test "__struct__/1 call" do
      assert list(clause(:struct_call_with_fields)) == [{:__struct__, 1, {:param, 0}}]
    end
  end
end
