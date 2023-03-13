defmodule Hologram.Compiler.PrunerTest do
  use Hologram.Test.UnitCase, async: false
  alias Hologram.Compiler.Pruner

  defp function_kept?(pruned_module, tested_module, function, arity, context) do
    result = Pruner.prune(pruned_module, context.module_defs, context.call_graph)

    if result[tested_module] do
      result[tested_module].functions
      |> Enum.any?(&(&1.arity == arity && &1.name == function))
    else
      false
    end
  end

  defp module_kept?(pruned_module, tested_module, context) do
    Pruner.prune(pruned_module, context.module_defs, context.call_graph)
    |> Map.has_key?(tested_module)
  end

  setup_all do
    opts = [
      app_path: @fixtures_path <> "/compiler/pruner",
      templatables: [Hologram.Test.Fixtures.App.DefaultLayout]
    ]

    compile(opts)
  end

  describe "kept page functions" do
    test "page actions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module1
      tested_module = pruned_module

      assert function_kept?(pruned_module, tested_module, :action, 3, context)
      assert function_kept?(pruned_module, tested_module, :action, 4, context)
    end

    test "functions reachable from page actions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module6
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module14

      assert function_kept?(pruned_module, tested_module, :test_fun_14a, 0, context)
    end

    test "page template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module15
      tested_module = pruned_module

      assert function_kept?(pruned_module, tested_module, :template, 0, context)
    end

    test "functions reachable from page template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module20
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module22

      assert function_kept?(pruned_module, tested_module, :test_22a, 0, context)
    end

    test "components reachable from page template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module29
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module31

      assert function_kept?(pruned_module, tested_module, :template, 0, context)
    end

    test "entry page layout function", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module48
      tested_module = pruned_module

      assert function_kept?(pruned_module, tested_module, :layout, 0, context)
    end

    test "entry page custom_layout function", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module51
      tested_module = pruned_module

      assert function_kept?(pruned_module, tested_module, :custom_layout, 0, context)
    end

    test "entry page route", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module54
      tested_module = pruned_module

      assert function_kept?(pruned_module, tested_module, :route, 0, context)
    end

    test "non-entry page route", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module55
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module56

      assert function_kept?(pruned_module, tested_module, :route, 0, context)
    end

    test "entry page __info__ function", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module64
      tested_module = pruned_module

      assert function_kept?(pruned_module, tested_module, :__info__, 1, context)
    end
  end

  describe "kept layout functions" do
    test "layout actions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module2
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module3

      assert function_kept?(pruned_module, tested_module, :action, 3, context)
      assert function_kept?(pruned_module, tested_module, :action, 4, context)
    end

    test "functions reachable from layout actions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module8
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module10

      assert function_kept?(pruned_module, tested_module, :test_fun_10a, 0, context)
    end

    test "layout template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module16
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module17

      assert function_kept?(pruned_module, tested_module, :template, 0, context)
    end

    test "functions reachable from layout template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module23
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module25

      assert function_kept?(pruned_module, tested_module, :test_25a, 0, context)
    end

    test "components reachable from layout template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module32
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module34

      assert function_kept?(pruned_module, tested_module, :template, 0, context)
    end

    test "layout init/1", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module38
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module39

      assert function_kept?(pruned_module, tested_module, :init, 1, context)
    end

    test "functions reachable from layout init/1", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module40
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module42

      assert function_kept?(pruned_module, tested_module, :test_fun_42a, 0, context)
    end
  end

  describe "kept component functions" do
    test "component actions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module4
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module5

      assert function_kept?(pruned_module, tested_module, :action, 3, context)
      assert function_kept?(pruned_module, tested_module, :action, 4, context)
    end

    test "functions reachable from component actions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module11
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module13

      assert function_kept?(pruned_module, tested_module, :test_fun_13a, 0, context)
    end

    test "component template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module18
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module19

      assert function_kept?(pruned_module, tested_module, :template, 0, context)
    end

    test "functions reachable from component template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module26
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module28

      assert function_kept?(pruned_module, tested_module, :test_28a, 0, context)
    end

    test "components reachable from component template", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module35
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module37

      assert function_kept?(pruned_module, tested_module, :template, 0, context)
    end

    test "component init/1", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module43
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module44

      assert function_kept?(pruned_module, tested_module, :init, 1, context)
    end

    test "functions reachable from component init/1", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module45
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module47

      assert function_kept?(pruned_module, tested_module, :test_fun_47a, 0, context)
    end
  end

  describe "pruned code" do
    test "non-entry page layout function", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module49
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module50

      refute function_kept?(pruned_module, tested_module, :layout, 0, context)
    end

    test "non-entry page custom_layout function", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module52
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module53

      refute function_kept?(pruned_module, tested_module, :custom_layout, 0, context)
    end

    test "non-entry page __info__ function", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module65
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module66

      refute function_kept?(pruned_module, tested_module, :__info__, 1, context)
    end

    test "unreachable pages", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module1
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module2

      refute module_kept?(pruned_module, tested_module, context)
    end

    test "unreachable functions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module57
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module58

      refute function_kept?(pruned_module, tested_module, :test_fun_58a, 0, context)
    end

    test "modules with unreachable-only functions", context do
      pruned_module = Hologram.Test.Fixtures.Compiler.Pruner.Module59
      tested_module = Hologram.Test.Fixtures.Compiler.Pruner.Module60

      refute module_kept?(pruned_module, tested_module, context)
    end
  end

  test "circular dependencies are handled correctly", context do
    module_61 = Hologram.Test.Fixtures.Compiler.Pruner.Module61
    module_62 = Hologram.Test.Fixtures.Compiler.Pruner.Module62
    module_63 = Hologram.Test.Fixtures.Compiler.Pruner.Module63

    assert function_kept?(module_61, module_62, :test_fun_62a, 0, context)
    assert function_kept?(module_61, module_63, :test_fun_63a, 0, context)
  end
end
