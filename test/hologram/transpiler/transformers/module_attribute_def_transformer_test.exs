defmodule Hologram.Transpiler.ModuleAttributeDefTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{IntegerType, ModuleAttributeDef}
  alias Hologram.Transpiler.ModuleAttributeDefTransformer

  test "transform/3" do
    result = ModuleAttributeDefTransformer.transform(:x, 1, [])
    expected = %ModuleAttributeDef{name: :x, value: %IntegerType{value: 1}}

    assert result == expected
  end
end
