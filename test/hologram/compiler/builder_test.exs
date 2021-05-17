defmodule Hologram.Compiler.BuilderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Builder

  test "build/1" do
    result = Builder.build([:Hologram, :Test, :Fixtures, :Compiler, :Builder, :Module1])

    assert result =~ ~r/^\nclass HologramTestFixturesCompilerBuilderModule1.+/
    assert result =~ ~r/\n\nclass HologramTestFixturesCompilerBuilderModule3.+/

    refute result =~ ~r/HologramTestFixturesCompilerBuilderModule2/
  end
end
