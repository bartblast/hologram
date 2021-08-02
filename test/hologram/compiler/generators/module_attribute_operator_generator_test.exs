defmodule Hologram.Compiler.ModuleAttributeOperatorGeneratorTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.{Context, ModuleAttributeOperatorGenerator, Opts}

  test "template opt" do
    context = %Context{module: Hologram.Compiler.ModuleAttributeOperatorGeneratorTest}
    opts = %Opts{template: true}

    result = ModuleAttributeOperatorGenerator.generate(:xyz, context, opts)
    expected = "Elixir_Hologram_Compiler_ModuleAttributeOperatorGeneratorTest.$xyz"

    assert result == expected
  end

  test "no template opt" do
    result = ModuleAttributeOperatorGenerator.generate(:xyz, %Context{}, %Opts{})
    expected = "$state.data['~atom[xyz]']"

    assert result == expected
  end
end
