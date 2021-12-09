defmodule Hologram.Compiler.IRAggregators.ComponentTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, ModuleDefinitionStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.Component
  alias Hologram.Test.Fixtures.Compiler.Aggregators.Component.{Module1, Module2, Module3}

  setup do
    ModuleDefinitionStore.create()
    :ok
  end

  test "aggregation from module body" do
    ir = %Component{module: Module1, props: %{}, children: []}

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module1)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module2)
  end

  test "aggregation from props" do
    ir = %Component{
      module: Module2,
      props: %{
        prop_1: %ModuleType{module: Module3}
      },
      children: []
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module2)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module3)
  end

  test "aggregation from children" do
    ir = %Component{
      module: Module2,
      props: %{},
      children: [%Component{module: Module3}]
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module2)
    assert %ModuleDefinition{} = ModuleDefinitionStore.get(Module3)
  end
end
