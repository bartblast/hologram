defmodule Hologram.Compiler.ModuleAttributeOperatorGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.{Context, ModuleAttributeOperatorGenerator, Opts}

  test "doesn't have template opt" do
    context = %Context{module: Hologram.Compiler.ModuleAttributeOperatorGeneratorTest}

    result = ModuleAttributeOperatorGenerator.generate(:xyz, context, %Opts{})
    expected = "Elixir_Hologram_Compiler_ModuleAttributeOperatorGeneratorTest.$xyz"

    assert result == expected
  end

  test "has template opt" do
    opts = %Opts{template: true}

    result = ModuleAttributeOperatorGenerator.generate(:xyz, %Context{}, opts)
    expected = "$state.data['~atom[xyz]']"

    assert result == expected
  end
end
