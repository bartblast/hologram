defmodule Hologram.Compiler.StructTypeGeneratorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Opts, StructTypeGenerator}
  alias Hologram.Compiler.IR.{AtomType, IntegerType}

  test "generate/4" do
    data = [{%AtomType{value: :a}, %IntegerType{value: 1}}]
    result = StructTypeGenerator.generate(Abc.Bcd, data, %Context{}, %Opts{})

    expected =
      "{ type: 'struct', module: 'Elixir_Abc_Bcd', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
