defmodule Hologram.Compiler.Aggregators.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Runtime.Commons
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.{Module1, Module2, Module6, Module7}
  alias Hologram.Test.Fixtures.PlaceholderModule1

  test "non standard lib module that isn't in the accumulator yet is added" do
    ir = %ModuleType{module: PlaceholderModule1}
    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [PlaceholderModule1]
    assert %ModuleDefinition{} = result[PlaceholderModule1]
  end

  test "module that is in the accumulator already is ignored" do
    ir = %ModuleType{module: PlaceholderModule1}

    result = Aggregator.aggregate(ir, %{})
    result = Aggregator.aggregate(ir, result)

    assert Map.keys(result) == [PlaceholderModule1]
    assert %ModuleDefinition{} = result[PlaceholderModule1]
  end

  test "standard lib module is ignored" do
    ir = %ModuleType{module: Kernel}
    result = Aggregator.aggregate(ir, %{})

    assert result == %{}
  end

  test "handles ignored modules" do
    ir = %ModuleType{module: Ecto.Changeset}
    result = Aggregator.aggregate(ir, %{})

    assert result == %{}
  end

  test "module that belongs to a namespace that is in the @ignored_namespaces is ignored" do
    ir = %ModuleType{module: Hologram.Commons.Encoder}
    result = Aggregator.aggregate(ir, %{})

    assert result == %{}
  end

  test "module functions are traversed" do
    ir = %ModuleType{module: Module1}
    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module1, Module2]
    assert %ModuleDefinition{} = result[Module1]
    assert %ModuleDefinition{} = result[Module2]
  end

  test "page default layout is added" do
    page = Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module3
    layout = Hologram.E2E.DefaultLayout

    ir = %ModuleType{module: page}
    result = Aggregator.aggregate(ir, %{})

    assert %ModuleDefinition{} = result[layout]
  end

  test "page custom layout is added" do
    page = Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module4
    layout = Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module5

    ir = %ModuleType{module: page}
    result = Aggregator.aggregate(ir, %{})

    assert %ModuleDefinition{} = result[layout]
  end

  test "aggregation from templetable module's template" do
    ir = %ModuleType{module: Module6}
    result = Aggregator.aggregate(ir, %{})

    # Hologram.Runtime.Commons module is added because templates use Hologram.Runtime.Commons.sigil_H/2
    assert Map.keys(result) == [Commons, Module6, Module7]
    assert %ModuleDefinition{} = result[Commons]
    assert %ModuleDefinition{} = result[Module6]
    assert %ModuleDefinition{} = result[Module7]
  end
end
