defmodule Hologram.Compiler.VariableEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.Variable

  describe "encode/3" do
    test "placeholder encoding" do
      ir = %Variable{name: :test}

      result = Encoder.encode(ir, %Context{}, %Opts{placeholder: true})
      expected = "{ type: 'placeholder' }"

      assert result == expected
    end

    test "non-placeholder encoding" do
      ir = %Variable{name: :test}

      result = Encoder.encode(ir, %Context{}, %Opts{})
      expected = "test"

      assert result == expected
    end
  end
end
