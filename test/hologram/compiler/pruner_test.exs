defmodule Hologram.Compiler.PrunerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Aggregator, Pruner}
  alias Hologram.Compiler.IR.ModuleType

  def function_kept?(page_module, tested_module, function, arity) do
    module_defs =
      %ModuleType{module: page_module}
      |> Aggregator.aggregate()


    result = Pruner.prune(module_defs, page_module)

    if result[tested_module] do
      result[tested_module].functions
      |> Enum.any?(&(&1.arity == arity && &1.name == function))
    else
      false
    end
  end

  describe "kept page functions" do
    test "page actions" do
      module_1 = Hologram.Test.Fixtures.Compiler.Pruner.Module1
      assert function_kept?(module_1, module_1, :action, 3)
      assert function_kept?(module_1, module_1, :action, 4)
    end

    test "functions reachable from page actions" do
      module_6 = Hologram.Test.Fixtures.Compiler.Pruner.Module6
      module_14 = Hologram.Test.Fixtures.Compiler.Pruner.Module14
      assert function_kept?(module_6, module_14, :test_fun_14a, 0)
    end

    test "page template" do
      module_15 = Hologram.Test.Fixtures.Compiler.Pruner.Module15
      assert function_kept?(module_15, module_15, :template, 0)
    end

    test "functions reachable from page template" do
      module_20 = Hologram.Test.Fixtures.Compiler.Pruner.Module20
      module_22 = Hologram.Test.Fixtures.Compiler.Pruner.Module22
      assert function_kept?(module_20, module_22, :test_22a, 0)
    end
  end

  describe "kept layout functions" do
    test "layout actions" do
      module_2 = Hologram.Test.Fixtures.Compiler.Pruner.Module2
      module_3 = Hologram.Test.Fixtures.Compiler.Pruner.Module3
      assert function_kept?(module_2, module_3, :action, 3)
      assert function_kept?(module_2, module_3, :action, 4)
    end

    test "functions reachable from layout actions" do
      module_8 = Hologram.Test.Fixtures.Compiler.Pruner.Module8
      module_10 = Hologram.Test.Fixtures.Compiler.Pruner.Module10
      assert function_kept?(module_8, module_10, :test_fun_10a, 0)
    end

    test "layout template" do
      module_16 = Hologram.Test.Fixtures.Compiler.Pruner.Module16
      module_17 = Hologram.Test.Fixtures.Compiler.Pruner.Module17
      assert function_kept?(module_16, module_17, :template, 0)
    end
  end

  describe "kept component functions" do
    test "component actions" do
      module_4 = Hologram.Test.Fixtures.Compiler.Pruner.Module4
      module_5 = Hologram.Test.Fixtures.Compiler.Pruner.Module5
      assert function_kept?(module_4, module_5, :action, 3)
      assert function_kept?(module_4, module_5, :action, 4)
    end

    test "functions reachable from component actions" do
      module_11 = Hologram.Test.Fixtures.Compiler.Pruner.Module11
      module_13 = Hologram.Test.Fixtures.Compiler.Pruner.Module13
      assert function_kept?(module_11, module_13, :test_fun_13a, 0)
    end

    test "component template" do
      module_18 = Hologram.Test.Fixtures.Compiler.Pruner.Module18
      module_19 = Hologram.Test.Fixtures.Compiler.Pruner.Module19
      assert function_kept?(module_18, module_19, :template, 0)
    end
  end
end
