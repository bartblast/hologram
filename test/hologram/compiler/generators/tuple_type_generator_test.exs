defmodule Hologram.Compiler.TupleTypeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, Opts, TupleTypeGenerator}
  alias Hologram.Compiler.IR.IntegerType

  test "generate/3" do
    data = [%IntegerType{value: 1}, %IntegerType{value: 2}]

    result = TupleTypeGenerator.generate(data, %Context{}, %Opts{})
    expected = "{ type: 'tuple', data: [ { type: 'integer', value: 1 }, { type: 'integer', value: 2 } ] }"

    assert result == expected
  end
end
