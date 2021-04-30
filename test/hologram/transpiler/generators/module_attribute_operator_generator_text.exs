defmodule Hologram.Transpiler.ModuleAttributeOperatorGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{IntegerType, ModuleAttributeDef}
  alias Hologram.Transpiler.ModuleAttributeOperatorGenerator

  test "generate/2" do
    context = [
      module_attributes: [
        %ModuleAttributeDef{name: :abc, value: %IntegerType{value: 1}},
        %ModuleAttributeDef{name: :bcd, value: %IntegerType{value: 2}},
        %ModuleAttributeDef{name: :cde, value: %IntegerType{value: 3}}
      ]
    ]

    result = ModuleAttributeOperatorGenerator.generate(:bcd, context)
    expected = "{ type: 'integer', value: 2 }"

    assert result == expected
  end
end
