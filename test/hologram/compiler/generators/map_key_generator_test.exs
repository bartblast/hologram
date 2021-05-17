defmodule Hologram.Compiler.MapKeyGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Compiler.MapKeyGenerator

  test "atom" do
    result = MapKeyGenerator.generate(%AtomType{value: :test})
    assert result == "~atom[test]"
  end

  test "boolean" do
    result = MapKeyGenerator.generate(%BooleanType{value: true})
    assert result == "~boolean[true]"
  end

  test "integer" do
    result = MapKeyGenerator.generate(%IntegerType{value: 123})
    assert result == "~integer[123]"
  end

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"})
    assert result == "~string[test]"
  end
end
