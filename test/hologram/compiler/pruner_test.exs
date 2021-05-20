defmodule Hologram.Compiler.PrunerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, FunctionDefinition}
  alias Hologram.Compiler.{Processor, Pruner}

  test "preserves actions of arity 3 and functions called from these actions" do
    main_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module1]
    compiled_modules = Processor.compile(main_module)

    result = Pruner.prune(compiled_modules, main_module)

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
    main_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module2]
    another_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module3]
    compiled_modules = Processor.compile(main_module)

    result = Pruner.prune(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 2
    assert Map.has_key?(result, main_module)
    assert Map.has_key?(result, another_module)

    assert [%FunctionDefinition{name: :action}] = result[main_module].functions
    assert [%FunctionDefinition{name: :test_3}] = result[another_module].functions
  end

  test "prunes unused modules" do
    main_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module4]
    compiled_modules = Processor.compile(main_module)

    result = Pruner.prune(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 1
    assert Map.has_key?(result, main_module)
  end

  test "handles Elixir standard library functions" do
    main_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module6]
    compiled_modules = Processor.compile(main_module)

    result = Pruner.prune(compiled_modules, main_module)

    assert (Map.keys(result) |> Enum.count()) == 1
    assert Map.has_key?(result, main_module)
  end
end
