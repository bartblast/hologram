defmodule Hologram.Transpiler.MapKeyGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Transpiler.MapKeyGenerator

  test "atom" do
    result = MapKeyGenerator.generate(%AtomType{value: :test})
    assert result == "~Hologram.Transpiler.AST.AtomType[test]"
  end

  test "boolean" do
    result = MapKeyGenerator.generate(%BooleanType{value: true})
    assert result == "~Hologram.Transpiler.AST.BooleanType[true]"
  end

  test "integer" do
    result = MapKeyGenerator.generate(%IntegerType{value: 123})
    assert result == "~Hologram.Transpiler.AST.IntegerType[123]"
  end

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"})
    assert result == "~Hologram.Transpiler.AST.StringType[test]"
  end
end
