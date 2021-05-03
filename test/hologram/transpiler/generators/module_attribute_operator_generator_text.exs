defmodule Hologram.Transpiler.ModuleAttributeOperatorGeneratorTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.ModuleAttributeOperatorGenerator

  test "generate/2" do
    context = [current_module: [:Abc, :Bcd]]

    result = ModuleAttributeOperatorGenerator.generate(:xyz, context)
    expected = "AbcBcd.$xyz"

    assert result == expected
  end
end
