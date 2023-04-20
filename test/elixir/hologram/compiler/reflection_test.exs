defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Reflection
  alias Hologram.Test.Fixtures.Compiler.Reflection.Module1

  describe "alias?/1" do
    test "atom which is an alias" do
      assert alias?(Calendar.ISO)
    end

    test "atom which is not an alias" do
      refute alias?(:abc)
    end

    test "non-atom" do
      refute alias?(123)
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

  test "module_beam_defs/1" do
    assert module_beam_defs(Module1) == [
             {{:fun_2, 2}, :def, [line: 7],
              [
                {[line: 7], [{:a, [version: 0, line: 7], nil}, {:b, [version: 1, line: 7], nil}],
                 [],
                 {{:., [line: 8], [:erlang, :+]}, [line: 8],
                  [{:a, [version: 0, line: 8], nil}, {:b, [version: 1, line: 8], nil}]}}
              ]},
             {{:fun_1, 0}, :def, [line: 3], [{[line: 3], [], [], :value_1}]}
           ]
  end
end
