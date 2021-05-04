defmodule Hologram.Transpiler.ModuleAttributeOperatorGeneratorTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.ModuleAttributeOperatorGenerator

  test "generate/2" do
    result = ModuleAttributeOperatorGenerator.generate(:xyz, [])
    expected = "$state.data.xyz"

    assert result == expected
  end
end
