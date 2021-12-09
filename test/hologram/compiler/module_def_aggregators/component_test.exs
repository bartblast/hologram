defmodule Hologram.Compiler.ModuleDefAggregators.ComponentTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.Component
  alias Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.Component.{Module1, Module2, Module3}

  setup do
    ModuleDefStore.create()
    :ok
  end

  test "aggregation from module body" do
    ir = %Component{module: Module1, props: %{}, children: []}

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(Module1)
    assert %ModuleDefinition{} = ModuleDefStore.get(Module2)
  end

  test "aggregation from props" do
    ir = %Component{
      module: Module2,
      props: %{
        prop_1: %ModuleType{module: Module3}
      },
      children: []
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(Module2)
    assert %ModuleDefinition{} = ModuleDefStore.get(Module3)
  end

  test "aggregation from children" do
    ir = %Component{
      module: Module2,
      props: %{},
      children: [%Component{module: Module3}]
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get(Module2)
    assert %ModuleDefinition{} = ModuleDefStore.get(Module3)
  end
end
