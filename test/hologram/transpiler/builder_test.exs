defmodule Hologram.Transpiler.BuilderTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Builder

  test "build/1" do
    result = Builder.build([:Hologram, :Transpiler, :Builder, :TestModule1])

    assert result =~ ~r/^\nclass HologramTranspilerBuilderTestModule1.+/
    assert result =~ ~r/\n\nclass HologramTranspilerBuilderTestModule3.+/

    refute result =~ ~r/HologramTranspilerBuilderTestModule2/
  end
end
