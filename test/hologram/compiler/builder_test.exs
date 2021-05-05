defmodule Hologram.Compiler.BuilderTest do
  use ExUnit.Case, async: true
  alias Hologram.Compiler.Builder

  test "build/1" do
    result = Builder.build([:Hologram, :Compiler, :Builder, :TestModule1])

    assert result =~ ~r/^\nclass HologramCompilerBuilderTestModule1.+/
    assert result =~ ~r/\n\nclass HologramCompilerBuilderTestModule3.+/

    refute result =~ ~r/HologramCompilerBuilderTestModule2/
  end
end
