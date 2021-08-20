defmodule Hologram.Compiler.PrunerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler
  alias Hologram.Compiler.Pruner

  @module_4 Hologram.Test.Fixtures.Compiler.Pruner.Module4
  @module_8 Hologram.Test.Fixtures.Compiler.Pruner.Module8
  @module_16 Hologram.Test.Fixtures.Compiler.Pruner.Module16

  describe "kept functions" do
    def test_module(compiled_module, expected_module, expected_function) do
      module_defs_map = Compiler.compile(compiled_module)
      result = Pruner.prune(module_defs_map, compiled_module)

      assert [function] = result[expected_module].functions
      assert function.name == expected_function
    end

    test "page actions" do
      module_1 = Hologram.Test.Fixtures.Compiler.Pruner.Module1
      module_defs_map = Compiler.compile(module_1)
      result = Pruner.prune(module_defs_map, module_1)

      assert [function_1, function_2, _] = result[module_1].functions
      assert function_1.name == :action
      assert function_1.arity == 3
      assert function_2.name == :action
      assert function_2.arity == 4
    end

    test "page template" do
      module_2 = Hologram.Test.Fixtures.Compiler.Pruner.Module2
      test_module(module_2, module_2, :template)
    end

    test "template of component used in page template" do
      module_3 = Hologram.Test.Fixtures.Compiler.Pruner.Module3
      test_module(module_3, @module_4, :template)
    end

    test "template of component used in component's slot used in page template" do
      module_5 = Hologram.Test.Fixtures.Compiler.Pruner.Module5
      test_module(module_5, @module_4, :template)
    end

    test "functions used by page actions" do
      module_7 = Hologram.Test.Fixtures.Compiler.Pruner.Module7
      test_module(module_7, @module_8, :test_8)
    end

    test "functions used by fuctions used by page actions" do
      module_10 = Hologram.Test.Fixtures.Compiler.Pruner.Module10
      test_module(module_10, @module_8, :test_8)
    end

    test "functions used in component props" do
      module_11 = Hologram.Test.Fixtures.Compiler.Pruner.Module11
      test_module(module_11, @module_8, :test_8)
    end

    test "functions used in element node attrs" do
      module_12 = Hologram.Test.Fixtures.Compiler.Pruner.Module12
      test_module(module_12, @module_8, :test_8)
    end

    test "functions used in text node expressions" do
      module_13 = Hologram.Test.Fixtures.Compiler.Pruner.Module13
      test_module(module_13, @module_8, :test_8)
    end

    test "functions used in nested nodes" do
      module_14 = Hologram.Test.Fixtures.Compiler.Pruner.Module14
      test_module(module_14, @module_8, :test_8)
    end
  end

  describe "pruned functions" do
    test "not used functions" do
      module_15 = Hologram.Test.Fixtures.Compiler.Pruner.Module15
      test_module(module_15, @module_16, :test_16a)
    end

    test "not used modules" do
      module_17 = Hologram.Test.Fixtures.Compiler.Pruner.Module17
      module_defs_map = Compiler.compile(module_17)
      result = Pruner.prune(module_defs_map, module_17)

      refute result[@module_16]
    end
  end

  test "handles circular dependency" do
    module_18 = Hologram.Test.Fixtures.Compiler.Pruner.Module18
    module_19 = Hologram.Test.Fixtures.Compiler.Pruner.Module19
    module_defs_map = Compiler.compile(module_18)
    result = Pruner.prune(module_defs_map, module_18)

    assert result[module_18]
    assert result[module_19]
  end
end
