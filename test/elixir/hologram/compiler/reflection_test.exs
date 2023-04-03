defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Reflection

  describe "is_alias?/1" do
    test "atom which is an alias" do
      assert is_alias?(Calendar.ISO)
    end

    test "atom which is not an alias" do
      refute is_alias?(:abc)
    end

    test "non-atom" do
      refute is_alias?(123)
    end
  end

  test "list_elixir_modules/1" do
    result = list_elixir_modules([:hologram, :dialyzer, :sobelow])

    assert Mix.Tasks.Sobelow in result
    assert Sobelow.CI in result
    assert Mix.Tasks.Holo.Test.CheckFileNames in result
    assert Hologram.Commons.Parser in result

    refute :dialyzer in result
    refute :typer_core in result
  end
end
