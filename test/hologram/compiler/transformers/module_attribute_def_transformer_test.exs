defmodule Hologram.Compiler.ModuleAttributeDefTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{IntegerType, ModuleAttributeDef}
  alias Hologram.Compiler.ModuleAttributeDefTransformer

  test "transform/3" do
    result = ModuleAttributeDefTransformer.transform(:x, 1, [])
    expected = %ModuleAttributeDef{name: :x, value: %IntegerType{value: 1}}

    assert result == expected
  end
end
