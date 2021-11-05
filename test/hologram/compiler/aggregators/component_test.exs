defmodule Hologram.Compiler.Aggregators.ComponentTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.Component
  alias Hologram.Test.Fixtures.Compiler.Aggregators.Component.{Module1, Module2, Module3}

  test "aggregation from module body" do
    ir = %Component{module: Module1, props: %{}, children: []}

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module1, Module2]
    assert %ModuleDefinition{} = result[Module1]
    assert %ModuleDefinition{} = result[Module2]
  end

  test "aggregation from props" do
    ir = %Component{
      module: Module2,
      props: %{
        prop_1: %ModuleType{module: Module3}
      },
      children: []
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module2, Module3]
    assert %ModuleDefinition{} = result[Module2]
    assert %ModuleDefinition{} = result[Module3]
  end

  test "aggregation from children" do
    ir = %Component{
      module: Module2,
      props: %{},
      children: [%Component{module: Module3}]
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module2, Module3]
    assert %ModuleDefinition{} = result[Module2]
    assert %ModuleDefinition{} = result[Module3]
  end
end
