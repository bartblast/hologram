defmodule Hologram.Compiler.MapKeyGeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MapKeyGenerator}
  alias Hologram.Compiler.IR.{IntegerType, StringType}

  test "string" do
    result = MapKeyGenerator.generate(%StringType{value: "test"}, %Context{})
    assert result == "~string[test]"
  end
end
