defmodule Hologram.Compiler.ListTypeGeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ListTypeGenerator, Opts}
  alias Hologram.Compiler.IR.IntegerType

  test "generate/3" do
    data = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = ListTypeGenerator.generate(data, %Context{}, %Opts{})

    expected =
      "{ type: 'list', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
