defmodule Hologram.Compiler.PrunerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.{Processor, Pruner}

  @module_1 Hologram.Test.Fixtures.Compiler.Pruner.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Pruner.Module2
  @module_3 Hologram.Test.Fixtures.Compiler.Pruner.Module3
  @module_4 Hologram.Test.Fixtures.Compiler.Pruner.Module4
  @module_5 Hologram.Test.Fixtures.Compiler.Pruner.Module5
  @module_6 Hologram.Test.Fixtures.Compiler.Pruner.Module6
  @module_7 Hologram.Test.Fixtures.Compiler.Pruner.Module7
  @module_8 Hologram.Test.Fixtures.Compiler.Pruner.Module8
  @module_9 Hologram.Test.Fixtures.Compiler.Pruner.Module9
  @module_10 Hologram.Test.Fixtures.Compiler.Pruner.Module10
  @module_11 Hologram.Test.Fixtures.Compiler.Pruner.Module11
  @module_12 Hologram.Test.Fixtures.Compiler.Pruner.Module12
  @module_13 Hologram.Test.Fixtures.Compiler.Pruner.Module13
  @module_14 Hologram.Test.Fixtures.Compiler.Pruner.Module14
  @module_15 Hologram.Test.Fixtures.Compiler.Pruner.Module15
  @module_16 Hologram.Test.Fixtures.Compiler.Pruner.Module16
  @module_17 Hologram.Test.Fixtures.Compiler.Pruner.Module17
  @module_18 Hologram.Test.Fixtures.Compiler.Pruner.Module18
  @module_19 Hologram.Test.Fixtures.Compiler.Pruner.Module19
  @module_20 Hologram.Test.Fixtures.Compiler.Pruner.Module20
  @module_21 Hologram.Test.Fixtures.Compiler.Pruner.Module21
  @module_22 Hologram.Test.Fixtures.Compiler.Pruner.Module22
  @module_23 Hologram.Test.Fixtures.Compiler.Pruner.Module23
  @module_24 Hologram.Test.Fixtures.Compiler.Pruner.Module24

  describe "pages" do
    test "preserves actions in pages" do
      module_defs_map = Processor.compile(@module_2)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_2)

      assert [function_1, function_2] = result[@module_2].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :action
      assert function_2.arity == 4
      assert hd(function_2.params) == %AtomType{value: :test_2}
    end

    test "preserves templates in pages" do
      module_defs_map = Processor.compile(@module_4)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_4)

      assert [function] = result[@module_4].functions

      assert function.name == :template
      assert function.arity == 0
      assert function.params == []
    end

    test "preserves route/0 function in pages" do
      module_defs_map = Processor.compile(@module_23)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_23)

      assert [function] = result[@module_23].functions

      assert function.name == :route
      assert function.arity == 0
      assert function.params == []
    end

    test "preserves functions in the same module called by page actions" do
      module_defs_map = Processor.compile(@module_7)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_7)

      assert [function_1, function_2] = result[@module_7].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in another module called by page actions" do
      module_defs_map = Processor.compile(@module_8)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 2

      assert Map.has_key?(result, @module_8)
      assert [function_1] = result[@module_8].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, @module_9)
      assert [function_2] = result[@module_9].functions

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in the same module called by other functions in the same module called by page actions" do
      module_defs_map = Processor.compile(@module_10)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_10)

      assert [function_1, function_2, function_3] = result[@module_10].functions

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
      module_defs_map = Processor.compile(@module_11)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 3

      assert Map.has_key?(result, @module_11)
      assert [function_1] = result[@module_11].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, @module_12)
      assert [function_2] = result[@module_12].functions

      assert function_2.name == :some_fun_1
      assert function_2.arity == 0
      assert function_2.params == []

      assert Map.has_key?(result, @module_13)
      assert [function_3] = result[@module_13].functions

      assert function_3.name == :some_fun_2
      assert function_3.arity == 0
      assert function_3.params == []
    end
  end

  describe "components" do
    test "preserves actions in components" do
      module_defs_map = Processor.compile(@module_3)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_3)

      assert [function_1, function_2] = result[@module_3].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :action
      assert function_2.arity == 4
      assert hd(function_2.params) == %AtomType{value: :test_2}
    end

    test "preserves templates in components" do
      module_defs_map = Processor.compile(@module_5)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_5)

      assert [function] = result[@module_5].functions

      assert function.name == :template
      assert function.arity == 0
      assert function.params == []
    end

    test "doesn't preserve route/0 function in components" do
      module_defs_map = Processor.compile(@module_24)
      assert Pruner.prune(module_defs_map) == %{}
    end

    test "preserves functions in the same module called by component actions" do
      module_defs_map = Processor.compile(@module_14)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_14)

      assert [function_1, function_2] = result[@module_14].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in another module called by component actions" do
      module_defs_map = Processor.compile(@module_15)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 2

      assert Map.has_key?(result, @module_15)
      assert [function_1] = result[@module_15].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, @module_16)
      assert [function_2] = result[@module_16].functions

      assert function_2.name == :some_fun
      assert function_2.arity == 0
      assert function_2.params == []
    end

    test "preserves functions in the same module called by other functions in the same module called by component actions" do
      module_defs_map = Processor.compile(@module_17)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_17)

      assert [function_1, function_2, function_3] = result[@module_17].functions

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
      module_defs_map = Processor.compile(@module_18)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 3

      assert Map.has_key?(result, @module_18)
      assert [function_1] = result[@module_18].functions

      assert function_1.name == :action
      assert function_1.arity == 3
      assert hd(function_1.params) == %AtomType{value: :test_1}

      assert Map.has_key?(result, @module_19)
      assert [function_2] = result[@module_19].functions

      assert function_2.name == :some_fun_1
      assert function_2.arity == 0
      assert function_2.params == []

      assert Map.has_key?(result, @module_20)
      assert [function_3] = result[@module_20].functions

      assert function_3.name == :some_fun_2
      assert function_3.arity == 0
      assert function_3.params == []
    end
  end

  describe "non-page and non-component modules" do
    test "doesn't preserve actions in modules other than pages or components" do
      module_defs_map = Processor.compile(@module_1)
      assert Pruner.prune(module_defs_map) == %{}
    end

    test "doesn't preserve templates in modules other than pages or components" do
      module_defs_map = Processor.compile(@module_6)
      assert Pruner.prune(module_defs_map) == %{}
    end

    test "handles Kernel functions" do
      module_defs_map = Processor.compile(@module_21)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_21)

      assert [function] = result[@module_21].functions

      assert function.name == :action
      assert function.arity == 3
      assert hd(function.params) == %AtomType{value: :test_1}
    end

    test "handles standard library functions" do
      module_defs_map = Processor.compile(@module_22)
      result = Pruner.prune(module_defs_map)

      assert Map.keys(result) |> Enum.count() == 1
      assert Map.has_key?(result, @module_22)

      assert [function] = result[@module_22].functions

      assert function.name == :action
      assert function.arity == 3
      assert hd(function.params) == %AtomType{value: :test_1}
    end
  end

  describe "functions used by templates" do
    def test_functions_used_by_templates(module) do
      module_defs_map = Processor.compile(module)
      result = Pruner.prune(module_defs_map)

      assert [%{name: :some_fun_2, arity: 0, params: []}] = result[@module_20].functions
    end

    test "function used in page template text node" do
      test_functions_used_by_templates(Hologram.Test.Fixtures.Compiler.Pruner.Module25)
    end

    test "function used in component template text node" do
      test_functions_used_by_templates(Hologram.Test.Fixtures.Compiler.Pruner.Module26)
    end

    test "function used in page template element node attribute" do
      test_functions_used_by_templates(Hologram.Test.Fixtures.Compiler.Pruner.Module27)
    end

    test "function used in component template element node attribute" do
      test_functions_used_by_templates(Hologram.Test.Fixtures.Compiler.Pruner.Module28)
    end

    test "function used in nested component template text node" do
      test_functions_used_by_templates(Hologram.Test.Fixtures.Compiler.Pruner.Module29)
    end

    test "function used in nested component template element node attribute" do
      test_functions_used_by_templates(Hologram.Test.Fixtures.Compiler.Pruner.Module30)
    end
  end
end
