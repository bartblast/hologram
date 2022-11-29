defmodule Hologram.Compiler.JSEncoder.FunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}

  alias Hologram.Compiler.IR.{
    BinaryType,
    FunctionCall,
    IntegerType,
    ListType,
    StringType
  }

  test "function name" do
    ir = %FunctionCall{
      function: :abc?,
      module: Test,
      args: []
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.abc$question()"

    assert result == expected
  end

  test "args" do
    ir = %FunctionCall{
      function: :abc,
      module: Test,
      args: [%IntegerType{value: 1}, %IntegerType{value: 2}]
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Test.abc({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end
end
