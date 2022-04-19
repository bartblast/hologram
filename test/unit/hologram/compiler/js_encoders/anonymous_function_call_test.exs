defmodule Hologram.Compiler.JSEncoder.AnonymousFunctionCallTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.JSEncoder
  alias Hologram.Compiler.Opts

  test "var name" do
    ir = %AnonymousFunctionCall{
      name: :abc?,
      args: []
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "abc$question.callback()"

    assert result == expected
  end

  test "args" do
    ir = %AnonymousFunctionCall{
      name: :abc,
      args: [%IntegerType{value: 1}, %IntegerType{value: 2}]
    }

    result = JSEncoder.encode(ir, %Context{}, %Opts{})
    expected = "abc.callback({ type: 'integer', value: 1 }, { type: 'integer', value: 2 })"

    assert result == expected
  end
end
