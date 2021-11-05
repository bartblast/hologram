defmodule Hologram.Compiler.Aggregators.ElementNodeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Aggregator
  alias Hologram.Compiler.IR.{ModuleDefinition, ModuleType}
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ElementNode.{Module1, Module2, Module3}

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

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module1, Module2, Module3]
    assert %ModuleDefinition{} = result[Module1]
    assert %ModuleDefinition{} = result[Module2]
    assert %ModuleDefinition{} = result[Module3]
  end

  test "aggregation from children" do
    ir = %ElementNode{
      attrs: %{},
      children: [
        %ModuleType{module: Module1},
        %ModuleType{module: Module2}
      ]
    }

    result = Aggregator.aggregate(ir, %{})

    assert Map.keys(result) == [Module1, Module2]
    assert %ModuleDefinition{} = result[Module1]
    assert %ModuleDefinition{} = result[Module2]
  end
end
