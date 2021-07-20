defmodule Hologram.Compiler.BuilderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Builder

  test "build/1" do
    result = Builder.build(Hologram.Test.Fixtures.Compiler.Builder.Module1)

    assert result =~ ~r/class Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module1/
    assert result =~ ~r/class Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module3/

    refute result =~ ~r/Elixir_Hologram_Test_Fixtures_Compiler_Builder_Module2/
  end
end
