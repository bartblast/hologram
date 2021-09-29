defmodule Hologram.Template.ComponentEncoderTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Template.Document.{Component, Expression, TextNode}
  alias Hologram.Template.Encoder

  test "encode/1" do
    module = Hologram.Test.Fixtures.Template.ComponentGenerator.Module1

    children = [
      %TextNode{content: "test_content"},
      %Expression{ir: %TupleType{data: [%IntegerType{value: 1}]}}
    ]

    result =
      %Component{module: module, children: children}
      |> Encoder.encode()

    expected_module = "Elixir_Hologram_Test_Fixtures_Template_ComponentGenerator_Module1"
    expected = "{ type: 'component', module: '#{expected_module}', children: [ { type: 'text', content: 'test_content' }, { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ { type: 'integer', value: 1 } ] } } } ] }"

    assert result == expected
  end
end
