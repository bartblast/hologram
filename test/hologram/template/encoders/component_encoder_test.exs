defmodule Hologram.Template.ComponentEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Template.Document.{Component, Expression, TextNode}
  alias Hologram.Template.Encoder

  describe "encode/1" do
    test "component doesn't have any props" do
      module = Hologram.Test.Fixtures.Template.ComponentEncoder.Module1

      children = [
        %TextNode{content: "test_content"},
        %Expression{ir: %TupleType{data: [%IntegerType{value: 1}]}}
      ]

      result =
        %Component{module: module, children: children, props: %{}}
        |> Encoder.encode()

      encoded_module = "Elixir_Hologram_Test_Fixtures_Template_ComponentEncoder_Module1"

      encoded_children =
        "[ { type: 'text', content: 'test_content' }, { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ { type: 'integer', value: 1 } ] } } } ]"

      expected =
        "{ type: 'component', module: '#{encoded_module}', children: #{encoded_children}, props: {} }"

      assert result == expected
    end

    test "component has single prop" do
      module = Hologram.Test.Fixtures.Template.ComponentEncoder.Module1

      props = %{
        prop_1: [%TextNode{content: "value_1"}]
      }

      result =
        %Component{module: module, children: [], props: props}
        |> Encoder.encode()

      encoded_module = "Elixir_Hologram_Test_Fixtures_Template_ComponentEncoder_Module1"
      encoded_props = "{ 'prop_1': [ { type: 'text', content: 'value_1' } ] }"

      expected =
        "{ type: 'component', module: '#{encoded_module}', children: [], props: #{encoded_props} }"

      assert result == expected
    end

    test "component has multiple props" do
      module = Hologram.Test.Fixtures.Template.ComponentEncoder.Module1

      props = %{
        prop_1: [%TextNode{content: "value_1"}],
        prop_2: [%TextNode{content: "value_2"}]
      }

      result =
        %Component{module: module, children: [], props: props}
        |> Encoder.encode()

      encoded_module = "Elixir_Hologram_Test_Fixtures_Template_ComponentEncoder_Module1"
      encoded_prop_1 = "'prop_1': [ { type: 'text', content: 'value_1' } ]"
      encoded_prop_2 = "'prop_2': [ { type: 'text', content: 'value_2' } ]"
      encoded_props = "{ #{encoded_prop_1}, #{encoded_prop_2} }"

      expected =
        "{ type: 'component', module: '#{encoded_module}', children: [], props: #{encoded_props} }"

      assert result == expected
    end
  end
end
