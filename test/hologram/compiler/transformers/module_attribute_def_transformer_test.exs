defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{IntegerType, ModuleAttributeDefinition}
  alias Hologram.Compiler.ModuleAttributeDefinitionTransformer

  test "transform/3" do
    result = ModuleAttributeDefinitionTransformer.transform(:x, 1, [])
    expected = %ModuleAttributeDefinition{name: :x, value: %IntegerType{value: 1}}

    assert result == expected
  end
end
