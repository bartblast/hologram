defmodule Hologram.Compiler.FunctionCallEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{BinaryType, FunctionCall, IntegerType, ListType, StringType, Variable}

  @ir %FunctionCall{
    function: :abc,
    module: Test,
    args: []
  }

  test "sigilH" do
    ir = %FunctionCall{
      function: :sigil_H,
      module: Hologram.Runtime.Commons,
      args: [
        %BinaryType{
          parts: [
            %StringType{value: "\n<div>Hello World {@counter}</div>\n"}
          ]
        },
        %ListType{data: []}
      ]
    }

    expected =
      "[ { type: 'element', tag: 'div', attrs: {}, children: [ { type: 'text', content: 'Hello World ' }, { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ $state.data['~atom[counter]'] ] } } } ] } ]"

    result = Encoder.encode(ir, %Context{}, %Opts{})
    assert result == expected
  end

  test "single arg" do
    args = [%IntegerType{value: 1}]
    ir = %{@ir | args: args}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end

  test "multiple args" do
    args = [%IntegerType{value: 1}, %IntegerType{value: 2}]
    ir = %{@ir | args: args}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end

  test "variable arg" do
    args = [%Variable{name: :x}]
    ir = %{@ir | args: args}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.abc(x)"

    assert result == expected
  end

  test "non-variable arg" do
    args = [%IntegerType{value: 1}]
    ir = %{@ir | args: args}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 })"

    assert result == expected
  end

  test "function name" do
    ir = %{@ir | function: :test?}

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.test$question()"

    assert result == expected
  end
end
