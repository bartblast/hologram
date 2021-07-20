defmodule Hologram.Compiler.MapKeyGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, MapKeyGenerator}
  alias Hologram.Compiler.IR.{AtomType, BooleanType, IntegerType, StringType}

  @context %Context{
    module: nil,
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

  test "atom" do
    result = MapKeyGenerator.generate(%AtomType{value: :test}, @context)
    assert result == "~atom[test]"
  end

  test "boolean" do
    result = MapKeyGenerator.generate(%BooleanType{value: true}, @context)
    assert result == "~boolean[true]"
  end

  test "integer" do
    result = MapKeyGenerator.generate(%IntegerType{value: 123}, @context)
    assert result == "~integer[123]"
  end

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"}, @context)
    assert result == "~string[test]"
  end
end
