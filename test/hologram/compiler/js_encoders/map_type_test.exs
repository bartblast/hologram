defmodule Hologram.Compiler.JSEncoder.MapTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AtomType, IntegerType, MapType}

  test "encode/3" do
    ir = %MapType{data: [{%AtomType{value: :a}, %IntegerType{value: 1}}]}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 } } }"

    assert result == expected
  end
end
