defmodule Hologram.Compiler.MapKeyGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Compiler.MapKeyGenerator

  test "atom" do
    result = MapKeyGenerator.generate(%AtomType{value: :test})
    assert result == "~Hologram.Compiler.AST.AtomType[test]"
  end

  test "boolean" do
    result = MapKeyGenerator.generate(%BooleanType{value: true})
    assert result == "~Hologram.Compiler.AST.BooleanType[true]"
  end

  test "integer" do
    result = MapKeyGenerator.generate(%IntegerType{value: 123})
    assert result == "~Hologram.Compiler.AST.IntegerType[123]"
  end

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"})
    assert result == "~Hologram.Compiler.AST.StringType[test]"
  end
end
