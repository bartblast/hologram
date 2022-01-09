defmodule Hologram.Compiler.JSEncoder.AccessOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.{AccessOperator, AtomType, IntegerType, MapType}

  test "encode/3" do
    ir = %AccessOperator{
      data: %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}}
        ]
      },
      key: %AtomType{value: :a}
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "Elixir_Access.get({ type: 'map', data: { '~atom[a]': { type: 'integer', value: 1 } } }, { type: 'atom', value: 'a' })"

    assert result == expected
  end
end
