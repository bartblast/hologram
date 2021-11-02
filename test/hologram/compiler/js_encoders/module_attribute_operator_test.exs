defmodule Hologram.Compiler.JSEncoder.ModuleAttributeOperatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, JSEncoder, Opts}
  alias Hologram.Compiler.IR.ModuleAttributeOperator

  @ir %ModuleAttributeOperator{name: :xyz}

  describe "encode/3" do
    test "when doesn't have template opt" do
      context = %Context{module: Hologram.Compiler.JSEncoder.ModuleAttributeOperatorTest}

      result = JSEncoder.encode(@ir, context, %Opts{})
      expected = "Elixir_Hologram_Compiler_JSEncoder_ModuleAttributeOperatorTest.$xyz"

      assert result == expected
    end

    test "when has template opt" do
      opts = %Opts{template: true}

      result = JSEncoder.encode(@ir, %Context{}, opts)
      expected = "$bindings.data['~atom[xyz]']"

      assert result == expected
    end
  end
end
