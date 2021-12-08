defmodule Hologram.Compiler.Aggregators.ElementNodeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{IRAggregator, IRStore}
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ElementNode.{Module1, Module2, Module3}

  setup do
    IRStore.create()
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

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = IRStore.get(Module1)
    assert %ModuleDefinition{} = IRStore.get(Module2)
    assert %ModuleDefinition{} = IRStore.get(Module3)
  end

  test "aggregation from children" do
    ir = %ElementNode{
      attrs: %{},
      children: [
        %ModuleType{module: Module1},
        %ModuleType{module: Module2}
      ]
    }

    IRAggregator.aggregate(ir)

    assert %ModuleDefinition{} = IRStore.get(Module1)
    assert %ModuleDefinition{} = IRStore.get(Module2)
  end
end
