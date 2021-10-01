defmodule Hologram.Compiler.ModuleAttributeDefinitionEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeDefinition}

  test "encode/3" do
    ir = %ModuleAttributeDefinition{
      name: :xyz,
      value: %IntegerType{value: 123}
    }

    result = Encoder.encode(ir, %Context{}, %Opts{})
    expected = "static $xyz = { type: 'integer', value: 123 };"

    assert result == expected
  end
end
