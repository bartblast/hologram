defmodule Hologram.Template.ComponentGeneratorTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Template.ComponentGenerator
  alias Hologram.Template.Document.{Expression, TextNode}

  test "generate/1" do
    module = Hologram.Test.Fixtures.Template.ComponentGenerator.Module1

    children = [
      %TextNode{content: "test_content"},
      %Expression{ir: %TupleType{data: [%IntegerType{value: 1}]}}
    ]

    result = ComponentGenerator.generate(module, children)

    expected_module = "Elixir_Hologram_Test_Fixtures_Template_ComponentGenerator_Module1"
    expected = "{ type: 'component', module: '#{expected_module}', children: [ { type: 'text', content: 'test_content' }, { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ { type: 'integer', value: 1 } ] } } } ] }"

    assert result == expected
  end
end
