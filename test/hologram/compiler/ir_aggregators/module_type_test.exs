defmodule Hologram.Compiler.IRAggregators.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, ModuleDefinitionStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Runtime.Commons
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.{Module1, Module2, Module6, Module7}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  setup do
    ModuleDefinitionStore.create()
    :ok
  end

  test "non standard lib module that isn't in the IR store yet is added" do
    ir = %ModuleType{module: PlaceholderModule1}
    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(PlaceholderModule1)
  end

  test "module that is in the IR store already is ignored" do
    ir = %ModuleType{module: PlaceholderModule1}

    IRAggregator.aggregate(ir)
    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(PlaceholderModule1)
  end

  test "standard lib module is ignored" do
    ir = %ModuleType{module: Kernel}
    IRAggregator.aggregate(ir)

    assert ModuleDefinitionStore.get(PlaceholderModule1) == nil
  end

  test "handles ignored modules" do
    ir = %ModuleType{module: Ecto.Changeset}
    IRAggregator.aggregate(ir)

    assert ModuleDefinitionStore.get(Ecto.Changeset) == nil
  end

  test "module that belongs to a namespace that is in the @ignored_namespaces is ignored" do
    ir = %ModuleType{module: Hologram.Commons.Encoder}
    IRAggregator.aggregate(ir)

    assert ModuleDefinitionStore.get(Hologram.Commons.Encoder) == nil
  end

  test "module functions are traversed" do
    ir = %ModuleType{module: Module1}
    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module1)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module2)
  end

  test "page default layout is added" do
    page = Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module3
    layout = Hologram.E2E.DefaultLayout
    ir = %ModuleType{module: page}

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(layout)
  end

  test "page custom layout is added" do
    page = Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module4
    layout = Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module5
    ir = %ModuleType{module: page}

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(layout)
  end

  test "aggregation from templetable module's template" do
    ir = %ModuleType{module: Module6}

    IRAggregator.aggregate(ir)

    # Hologram.Runtime.Commons module is added because templates use Hologram.Runtime.Commons.sigil_H/2
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Commons)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module6)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module7)
  end
end
