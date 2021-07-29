defmodule Hologram.Compiler.MapKeyGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, MapKeyGenerator}
  alias Hologram.Compiler.IR.{AtomType, BooleanType, IntegerType, StringType}

  test "atom" do
    result = MapKeyGenerator.generate(%AtomType{value: :test}, %Context{})
    assert result == "~atom[test]"
  end

  test "boolean" do
    result = MapKeyGenerator.generate(%BooleanType{value: true}, %Context{})
    assert result == "~boolean[true]"
  end

  test "integer" do
    result = MapKeyGenerator.generate(%IntegerType{value: 123}, %Context{})
    assert result == "~integer[123]"
  end

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"}, %Context{})
    assert result == "~string[test]"
  end
end
