defmodule Hologram.Compiler.PrunerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler
  alias Hologram.Compiler.Pruner

  @default_layout Application.get_env(:hologram, :default_layout)
  @module_4 Hologram.Test.Fixtures.Compiler.Pruner.Module4
  @module_8 Hologram.Test.Fixtures.Compiler.Pruner.Module8
  @module_16 Hologram.Test.Fixtures.Compiler.Pruner.Module16
  @module_20 Hologram.Test.Fixtures.Compiler.Pruner.Module20

  describe "kept functions" do
    def function_preserved?(compiled_module, tested_module, function_name, function_arity) do
      module_defs_map = Compiler.compile(compiled_module)

      result = Pruner.prune(module_defs_map, compiled_module)

      if result[tested_module] do
        result[tested_module].functions
        |> Enum.any?(fn %{arity: arity, name: name} ->
          arity == function_arity && name == function_name
        end)
      else
        false
      end
    end

    test "page actions" do
      module_1 = Hologram.Test.Fixtures.Compiler.Pruner.Module1
      assert function_preserved?(module_1, module_1, :action, 3)
      assert function_preserved?(module_1, module_1, :action, 4)
    end

    test "page template" do
      module_2 = Hologram.Test.Fixtures.Compiler.Pruner.Module2
      assert function_preserved?(module_2, module_2, :template, 0)
    end

    test "layout template" do
      module_2 = Hologram.Test.Fixtures.Compiler.Pruner.Module2
      assert function_preserved?(module_2, @default_layout, :template, 0)
    end

    test "template of component used in page template" do
      module_3 = Hologram.Test.Fixtures.Compiler.Pruner.Module3
      assert function_preserved?(module_3, @module_4, :template, 0)
    end

    test "template of component used in component's slot used in page template" do
      module_5 = Hologram.Test.Fixtures.Compiler.Pruner.Module5
      assert function_preserved?(module_5, @module_4, :template, 0)
    end

    test "functions used by page actions" do
      module_7 = Hologram.Test.Fixtures.Compiler.Pruner.Module7
      assert function_preserved?(module_7, @module_8, :test_8, 0)
    end

    test "functions used by fuctions used by page actions" do
      module_10 = Hologram.Test.Fixtures.Compiler.Pruner.Module10
      assert function_preserved?(module_10, @module_8, :test_8, 0)
    end

    test "functions used in component props" do
      module_11 = Hologram.Test.Fixtures.Compiler.Pruner.Module11
      assert function_preserved?(module_11, @module_8, :test_8, 0)
    end

    test "functions used in element node attrs" do
      module_12 = Hologram.Test.Fixtures.Compiler.Pruner.Module12
      assert function_preserved?(module_12, @module_8, :test_8, 0)
    end

    test "functions used in text node expressions" do
      module_13 = Hologram.Test.Fixtures.Compiler.Pruner.Module13
      assert function_preserved?(module_13, @module_8, :test_8, 0)
    end

    test "functions used in nested nodes" do
      module_14 = Hologram.Test.Fixtures.Compiler.Pruner.Module14
      assert function_preserved?(module_14, @module_8, :test_8, 0)
    end

    test "layout function of the pruned page module" do
      assert function_preserved?(@module_20, @module_20, :layout, 0)
    end

    test "functions used inside if expression" do
      module_22 = Hologram.Test.Fixtures.Compiler.Pruner.Module22
      assert function_preserved?(module_22, @module_20, :fun_1, 0)
      assert function_preserved?(module_22, @module_20, :fun_2, 0)
      assert function_preserved?(module_22, @module_20, :fun_3, 0)
    end

    test "functions used in function call params" do
      module_23 = Hologram.Test.Fixtures.Compiler.Pruner.Module23
      assert function_preserved?(module_23, @module_20, :fun_1, 0)
    end
  end

  describe "pruned functions" do
    test "layout function of a page module other than the pruned one" do
      module_21 = Hologram.Test.Fixtures.Compiler.Pruner.Module21
      refute function_preserved?(module_21, @module_20, :layout, 0)
    end

    test "not used functions" do
      module_15 = Hologram.Test.Fixtures.Compiler.Pruner.Module15
      refute function_preserved?(module_15, @module_16, :test_16b, 0)
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
