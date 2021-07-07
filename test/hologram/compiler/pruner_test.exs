defmodule Hologram.Compiler.PrunerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.{Processor, Pruner}

  describe "pages" do
    test "preserves actions in pages" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module2]
      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function_1, function_2] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :action
      assert function_2.arity == 4
      assert hd(function_2.params) == %AtomType{value: :test_2}
    end

    test "preserves templates in pages" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module4]
      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function] = result[entry_module].functions

      assert function.name == :template
      assert function.arity == 0
      assert function.params == []
    end

    test "preserves functions in the same module called by page actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module7]
      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function_1, function_2] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in another module called by page actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module8]
      aliased_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module9]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 2

      assert Map.has_key?(result, entry_module)
      assert [function_1] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, aliased_module)
      assert [function_2] = result[aliased_module].functions

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in the same module called by other functions in the same module called by page actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module10]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function_1, function_2, function_3] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :some_fun_1
      assert function_2.arity == 0
      assert function_2.params == []

      assert function_3.name == :some_fun_2
      assert function_3.arity == 0
      assert function_3.params == []
    end

    test "preserves functions in another module called by other functions in another module called by page actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module11]
      aliased_module_1 = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module12]
      aliased_module_2 = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module13]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 3

      assert Map.has_key?(result, entry_module)
      assert [function_1] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, aliased_module_1)
      assert [function_2] = result[aliased_module_1].functions

      assert function_2.name == :some_fun_1
      assert function_2.arity == 0
      assert function_2.params == []

      assert Map.has_key?(result, aliased_module_2)
      assert [function_3] = result[aliased_module_2].functions

      assert function_3.name == :some_fun_2
      assert function_3.arity == 0
      assert function_3.params == []
    end
  end

  describe "components" do
    test "preserves actions in components" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module3]
      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function_1, function_2] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :action
      assert function_2.arity == 4
      assert hd(function_2.params) == %AtomType{value: :test_2}
    end

    test "preserves templates in components" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module5]
      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function] = result[entry_module].functions

      assert function.name == :template
      assert function.arity == 0
      assert function.params == []
    end

    test "preserves functions in the same module called by component actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module14]
      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function_1, function_2] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in another module called by component actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module15]
      aliased_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module16]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 2

      assert Map.has_key?(result, entry_module)
      assert [function_1] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, aliased_module)
      assert [function_2] = result[aliased_module].functions

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in the same module called by other functions in the same module called by component actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module17]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function_1, function_2, function_3] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :some_fun_1
      assert function_2.arity == 0
      assert function_2.params == []

      assert function_3.name == :some_fun_2
      assert function_3.arity == 0
      assert function_3.params == []
    end

    test "preserves functions in another module called by other functions in another module called by component actions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module18]
      aliased_module_1 = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module19]
      aliased_module_2 = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module20]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 3

      assert Map.has_key?(result, entry_module)
      assert [function_1] = result[entry_module].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, aliased_module_1)
      assert [function_2] = result[aliased_module_1].functions

      assert function_2.name == :some_fun_1
      assert function_2.arity == 0
      assert function_2.params == []

      assert Map.has_key?(result, aliased_module_2)
      assert [function_3] = result[aliased_module_2].functions

      assert function_3.name == :some_fun_2
      assert function_3.arity == 0
      assert function_3.params == []
    end
  end

  describe "non-page and non-component modules" do
    test "doesn't preserve actions in modules other than pages or components" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module1]
      module_defs_map = Processor.compile(entry_module)

      assert Pruner.prune(module_defs_map) == %{}
    end

    test "doesn't preserve templates in modules other than pages or components" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module6]
      module_defs_map = Processor.compile(entry_module)

      assert Pruner.prune(module_defs_map) == %{}
    end

    test "handles Kernel functions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module21]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function] = result[entry_module].functions

      assert function.name == :action
      assert function.arity == 3
      assert hd(function.params) == %AtomType{value: :test_1}
    end

    test "handles standard library functions" do
      entry_module = [:Hologram, :Test, :Fixtures, :Compiler, :Pruner, :Module22]

      module_defs_map = Processor.compile(entry_module)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, entry_module)

      assert [function] = result[entry_module].functions

      assert function.name == :action
      assert function.arity == 3
      assert hd(function.params) == %AtomType{value: :test_1}
    end
  end
end
