defmodule Hologram.Compiler.PrunerTest do
  use Hologram.Test.UnitCase, async: false
  alias Hologram.Compiler.{CallGraph, CallGraphBuilder, ModuleDefAggregator, ModuleDefStore, Pruner}

  def function_kept?(page_module, tested_module, function, arity) do
    ModuleDefAggregator.aggregate(page_module)
    ModuleDefAggregator.aggregate(tested_module)
    module_defs = ModuleDefStore.get_all()

    CallGraphBuilder.build(page_module, module_defs)
    CallGraphBuilder.build(tested_module, module_defs)
    call_graph = CallGraph.get()

    result = Pruner.prune(page_module, module_defs, call_graph)

    if result[tested_module] do
      result[tested_module].functions
      |> Enum.any?(&(&1.arity == arity && &1.name == function))
    else
      false
    end
  end

  setup do
    ModuleDefStore.create()
    CallGraph.create()
    :ok
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

    test "components reachable from page template" do
      module_29 = Hologram.Test.Fixtures.Compiler.Pruner.Module29
      module_31 = Hologram.Test.Fixtures.Compiler.Pruner.Module31
      assert function_kept?(module_29, module_31, :template, 0)
    end

    test "entry page layout function" do
      module_48 = Hologram.Test.Fixtures.Compiler.Pruner.Module48
      assert function_kept?(module_48, module_48, :layout, 0)
    end

    test "entry page custom_layout function" do
      module_51 = Hologram.Test.Fixtures.Compiler.Pruner.Module51
      assert function_kept?(module_51, module_51, :custom_layout, 0)
    end

    test "entry page route" do
      module_54 = Hologram.Test.Fixtures.Compiler.Pruner.Module54
      assert function_kept?(module_54, module_54, :route, 0)
    end

    test "non-entry page route" do
      module_55 = Hologram.Test.Fixtures.Compiler.Pruner.Module55
      module_56 = Hologram.Test.Fixtures.Compiler.Pruner.Module56
      assert function_kept?(module_55, module_56, :route, 0)
    end

    test "entry page __info__ function" do
      module_64 = Hologram.Test.Fixtures.Compiler.Pruner.Module64
      assert function_kept?(module_64, module_64, :__info__, 1)
    end
  end

  describe "pruned page functions" do
    test "non-entry page layout function" do
      module_49 = Hologram.Test.Fixtures.Compiler.Pruner.Module49
      module_50 = Hologram.Test.Fixtures.Compiler.Pruner.Module50
      refute function_kept?(module_49, module_50, :layout, 0)
    end

    test "non-entry page custom_layout function" do
      module_52 = Hologram.Test.Fixtures.Compiler.Pruner.Module52
      module_53 = Hologram.Test.Fixtures.Compiler.Pruner.Module53
      refute function_kept?(module_52, module_53, :custom_layout, 0)
    end

    test "non-entry page __info__ function" do
      module_65 = Hologram.Test.Fixtures.Compiler.Pruner.Module65
      module_66 = Hologram.Test.Fixtures.Compiler.Pruner.Module66
      refute function_kept?(module_65, module_66, :__info__, 1)
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

    test "functions reachable from layout template" do
      module_23 = Hologram.Test.Fixtures.Compiler.Pruner.Module23
      module_25 = Hologram.Test.Fixtures.Compiler.Pruner.Module25
      assert function_kept?(module_23, module_25, :test_25a, 0)
    end

    test "components reachable from layout template" do
      module_32 = Hologram.Test.Fixtures.Compiler.Pruner.Module32
      module_34 = Hologram.Test.Fixtures.Compiler.Pruner.Module34
      assert function_kept?(module_32, module_34, :template, 0)
    end

    test "layout init" do
      module_38 = Hologram.Test.Fixtures.Compiler.Pruner.Module38
      module_39 = Hologram.Test.Fixtures.Compiler.Pruner.Module39
      assert function_kept?(module_38, module_39, :init, 0)
    end

    test "functions reachable from layout init" do
      module_40 = Hologram.Test.Fixtures.Compiler.Pruner.Module40
      module_42 = Hologram.Test.Fixtures.Compiler.Pruner.Module42
      assert function_kept?(module_40, module_42, :test_fun_42a, 0)
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

    test "functions reachable from component template" do
      module_26 = Hologram.Test.Fixtures.Compiler.Pruner.Module26
      module_28 = Hologram.Test.Fixtures.Compiler.Pruner.Module28
      assert function_kept?(module_26, module_28, :test_28a, 0)
    end

    test "components reachable from component template" do
      module_35 = Hologram.Test.Fixtures.Compiler.Pruner.Module35
      module_37 = Hologram.Test.Fixtures.Compiler.Pruner.Module37
      assert function_kept?(module_35, module_37, :template, 0)
    end

    test "component init" do
      module_43 = Hologram.Test.Fixtures.Compiler.Pruner.Module43
      module_44 = Hologram.Test.Fixtures.Compiler.Pruner.Module44
      assert function_kept?(module_43, module_44, :init, 0)
    end

    test "functions reachable from component init" do
      module_45 = Hologram.Test.Fixtures.Compiler.Pruner.Module45
      module_47 = Hologram.Test.Fixtures.Compiler.Pruner.Module47
      assert function_kept?(module_45, module_47, :test_fun_47a, 0)
    end
  end

  test "unreachable functions are pruned" do
    module_57 = Hologram.Test.Fixtures.Compiler.Pruner.Module57
    module_58 = Hologram.Test.Fixtures.Compiler.Pruner.Module58
    refute function_kept?(module_57, module_58, :test_fun_58a, 0)
  end

  test "modules with unreachable-only functions are pruned" do
    module_59 = Hologram.Test.Fixtures.Compiler.Pruner.Module59
    module_60 = Hologram.Test.Fixtures.Compiler.Pruner.Module60

    ModuleDefAggregator.aggregate(module_59)
    module_defs = ModuleDefStore.get_all()

    CallGraphBuilder.build(module_59, module_defs)
    call_graph = CallGraph.get()

    result = Pruner.prune(module_59, module_defs, call_graph)

    refute Map.has_key?(result, module_60)
  end

  test "circular dependencies are handled correctly" do
    module_61 = Hologram.Test.Fixtures.Compiler.Pruner.Module61
    module_62 = Hologram.Test.Fixtures.Compiler.Pruner.Module62
    module_63 = Hologram.Test.Fixtures.Compiler.Pruner.Module63

    assert function_kept?(module_61, module_62, :test_fun_62a, 0)
    assert function_kept?(module_61, module_63, :test_fun_63a, 0)
  end
end
