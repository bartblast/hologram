defmodule Hologram.Compiler.AtomTypeEncoderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Encoder, Opts}
  alias Hologram.Compiler.IR.ModuleAttributeOperator

  @ir %ModuleAttributeOperator{name: :xyz}

  describe "encode/3" do
    test "when doesn't have template opt" do
      context = %Context{module: Hologram.Compiler.ModuleAttributeOperatorGeneratorTest}

      result = Encoder.encode(@ir, context, %Opts{})
      expected = "Elixir_Hologram_Compiler_ModuleAttributeOperatorGeneratorTest.$xyz"

      assert result == expected
    end

    test "when has template opt" do
      opts = %Opts{template: true}

      result = Encoder.encode(@ir, %Context{}, opts)
      expected = "$state.data['~atom[xyz]']"

      assert result == expected
    end
  end
end
