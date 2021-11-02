defmodule Hologram.Compiler.JSEncoder.ModuleTypeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.ModuleType

  test "encode/3" do
    ir = %ModuleType{module: Abc.Bcd}

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "{ type: 'module', className: 'Elixir_Abc_Bcd' }"

    assert result == expected
  end
end
