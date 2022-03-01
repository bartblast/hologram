defmodule Hologram.Compiler.JSEncoder.StructTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, IntegerType, StructType}

  test "encode/3" do
    ir = %StructType{
      data: [{%AtomType{value: :a}, %IntegerType{value: 1}}],
      module: Abc.Bcd
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})

    expected =
      "{ type: 'struct', className: 'Elixir_Abc_Bcd', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
