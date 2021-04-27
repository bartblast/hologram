defmodule Hologram.Transpiler.EliminatorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler
  alias Hologram.Transpiler.AST.{AtomType, Function}
  alias Hologram.Transpiler.Eliminator

  test "preserves actions of arity 3 and functions called from these actions" do
    main_module = [:Hologram, :Transpiler, :Eliminator, :TestModule1]
    compiled_modules = Compiler.compile(main_module)

    result = Eliminator.eliminate(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 1
    assert Map.has_key?(result, main_module)

    assert [function_1, function_2, function_3] = result[main_module].functions

    assert function_1.name == :action
    assert function_1.arity == 3
    assert hd(function_1.params) == %AtomType{value: :test_1}

    assert function_2.name == :action
    assert function_2.arity == 3
    assert hd(function_2.params) == %AtomType{value: :test_3}

    assert function_3.name == :called_function
  end

  test "preserves used functions from another module" do
    main_module = [:Hologram, :Transpiler, :Eliminator, :TestModule2]
    another_module = [:Hologram, :Transpiler, :Eliminator, :TestModule3]
    compiled_modules = Compiler.compile(main_module)

    result = Eliminator.eliminate(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 2
    assert Map.has_key?(result, main_module)
    assert Map.has_key?(result, another_module)

    assert [%Function{name: :action}] = result[main_module].functions
    assert [%Function{name: :test_3}] = result[another_module].functions
  end

  test "purges redundant modules" do
    main_module = [:Hologram, :Transpiler, :Eliminator, :TestModule4]
    compiled_modules = Compiler.compile(main_module)

    result = Eliminator.eliminate(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 1
    assert Map.has_key?(result, main_module)
  end

  test "handles Elixir standard library functions" do
    main_module = [:Hologram, :Transpiler, :Eliminator, :TestModule6]
    compiled_modules = Compiler.compile(main_module)

    result = Eliminator.eliminate(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 1
    assert Map.has_key?(result, main_module)
  end
end
