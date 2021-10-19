defmodule Hologram.Compiler.MapKeyGeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapKeyGenerator}
  alias Hologram.Compiler.IR.{IntegerType, StringType}

  test "integer" do
    result = MapKeyGenerator.generate(%IntegerType{value: 123}, %Context{})
    assert result == "~integer[123]"
  end

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"}, %Context{})
    assert result == "~string[test]"
  end
end
