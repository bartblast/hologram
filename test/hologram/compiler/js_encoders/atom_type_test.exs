defmodule Hologram.Compiler.JSEncoder.AtomTyperTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.AtomType

  test "encode/3" do
    ir = %AtomType{value: :test}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'atom', value: 'test' }"

    assert result == expected
  end
end
