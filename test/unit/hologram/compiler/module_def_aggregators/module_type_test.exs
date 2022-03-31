defmodule Hologram.Compiler.ModuleDefAggregators.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Runtime.{Commons, TemplateStore}

  alias Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.{
    Module1,
    Module2,
    Module3,
    Module4,
    Module6,
    Module7
  }

  alias Hologram.Test.Fixtures.PlaceholderModule1

  setup do
    ModuleDefStore.create()
    TemplateStore.reset()

    [Module3, Module4, Module6, Module7, HologramE2E.DefaultLayout]
    |> seed_template_store()

    :ok
  end

  test "non standard lib module that isn't in the IR store yet is added" do
    ir = %ModuleType{module: PlaceholderModule1}
    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule1)
  end

  test "module that is in the IR store already is ignored" do
    ir = %ModuleType{module: PlaceholderModule1}

    ModuleDefAggregator.aggregate(ir)
    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(PlaceholderModule1)
  end

  test "standard lib module is ignored" do
    ir = %ModuleType{module: Kernel}
    ModuleDefAggregator.aggregate(ir)

    assert ModuleDefStore.get!(PlaceholderModule1) == nil
  end

  test "handles ignored modules" do
    ir = %ModuleType{module: Ecto.Changeset}
    ModuleDefAggregator.aggregate(ir)

    assert ModuleDefStore.get!(Ecto.Changeset) == nil
  end

  test "module that belongs to a namespace that is in the @ignored_namespaces is ignored" do
    ir = %ModuleType{module: Hologram.Commons.Encoder}
    ModuleDefAggregator.aggregate(ir)

    assert ModuleDefStore.get!(Hologram.Commons.Encoder) == nil
  end

  test "module functions are traversed" do
    ir = %ModuleType{module: Module1}
    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(Module1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module2)
  end

  test "page default layout is added" do
    page = Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.Module3
    layout = HologramE2E.DefaultLayout
    ir = %ModuleType{module: page}

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(layout)
  end

  test "page custom layout is added" do
    page = Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.Module4
    layout = Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.Module5
    ir = %ModuleType{module: page}

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(layout)
  end

  test "aggregation from templetable module's template" do
    ir = %ModuleType{module: Module6}

    ModuleDefAggregator.aggregate(ir)

    # Hologram.Runtime.Commons module is added because templates use Hologram.Runtime.Commons.sigil_H/2
    assert %ModuleDefinition{} = ModuleDefStore.get!(Commons)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module6)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module7)
  end
end
