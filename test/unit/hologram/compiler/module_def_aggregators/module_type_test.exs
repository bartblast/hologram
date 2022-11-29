defmodule Hologram.Compiler.ModuleDefAggregator.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}

  alias Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.{
    Module1,
    Module2,
    Module6,
    Module7
  }

  alias Hologram.Test.Fixtures.PlaceholderModule1

  setup do
    [
      app_path: @fixtures_path <> "/compiler/module_def_aggregators/module_type",
      templatables: [Hologram.Test.Fixtures.App.DefaultLayout]
    ]
    |> compile()

    ModuleDefStore.run()

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

    assert ModuleDefStore.get(PlaceholderModule1) == :error
  end

  test "handles ignored modules" do
    ir = %ModuleType{module: Ecto.Changeset}
    ModuleDefAggregator.aggregate(ir)

    assert ModuleDefStore.get(Ecto.Changeset) == :error
  end

  test "module that belongs to a namespace that is in the @ignored_namespaces is ignored" do
    ir = %ModuleType{module: Hologram.Commons.Encoder}
    ModuleDefAggregator.aggregate(ir)

    assert ModuleDefStore.get(Hologram.Commons.Encoder) == :error
  end

  test "module functions are traversed" do
    ir = %ModuleType{module: Module1}
    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(Module1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module2)
  end

  test "page default layout is added" do
    page = Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.Module3
    layout = Hologram.Test.Fixtures.App.DefaultLayout
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

    assert %ModuleDefinition{} = ModuleDefStore.get!(Module6)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module7)
  end
end
