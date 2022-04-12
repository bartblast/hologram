defmodule Hologram.Compiler.ModuleDefAggregator.ElementNodeTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.ElementNode

  alias Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ElementNode.{
    Module1,
    Module2,
    Module3
  }

  setup do
    ModuleDefStore.run()
    :ok
  end

  test "aggregation from attrs" do
    ir = %ElementNode{
      attrs: %{
        attr_1: %{
          value: [
            %ModuleType{module: Module1},
            %ModuleType{module: Module2}
          ],
          modifiers: []
        },
        attr_2: %{
          value: [
            %ModuleType{module: Module3}
          ],
          modifiers: []
        }
      },
      children: []
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(Module1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module2)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module3)
  end

  test "aggregation from children" do
    ir = %ElementNode{
      attrs: %{},
      children: [
        %ModuleType{module: Module1},
        %ModuleType{module: Module2}
      ]
    }

    ModuleDefAggregator.aggregate(ir)

    assert %ModuleDefinition{} = ModuleDefStore.get!(Module1)
    assert %ModuleDefinition{} = ModuleDefStore.get!(Module2)
  end
end
