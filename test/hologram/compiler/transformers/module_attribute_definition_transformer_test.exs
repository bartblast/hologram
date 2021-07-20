defmodule Hologram.Compiler.ModuleAttributeDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ModuleAttributeDefinitionTransformer}
  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeDefinition}

  test "transform/3" do
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    result = ModuleAttributeDefinitionTransformer.transform(:x, 1, context)
    expected = %ModuleAttributeDefinition{name: :x, value: %IntegerType{value: 1}}

    assert result == expected
  end
end
