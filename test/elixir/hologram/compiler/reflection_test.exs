defmodule Hologram.Compiler.ReflectionTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Reflection

  alias Hologram.Test.Fixtures.Compiler.Reflection.Module1
  alias Hologram.Test.Fixtures.Compiler.Reflection.Module2
  alias Hologram.Test.Fixtures.Compiler.Reflection.Module3
  alias Hologram.Test.Fixtures.Compiler.Reflection.Module4

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

  describe "component?" do
    test "is a component module" do
      assert component?(Module3)
    end

    test "is not a module" do
      refute component?(123)
    end

    test "is not a component module" do
      refute component?(__MODULE__)
    end
  end

  describe "layout?" do
    test "is a layout module" do
      assert layout?(Module4)
    end

    test "is not a module" do
      refute layout?(123)
    end

    test "is not a layout module" do
      refute layout?(__MODULE__)
    end
  end

  test "list_elixir_modules/1" do
    result = list_elixir_modules([:hologram, :dialyzer, :sobelow])

    assert Mix.Tasks.Sobelow in result
    assert Sobelow.CI in result
    assert Mix.Tasks.Holo.Test.CheckFileNames in result
    assert Hologram.Template.Tokenizer in result

    refute :dialyzer in result
    refute :typer_core in result
  end

  test "list_loaded_otp_apps/0" do
    result = list_loaded_otp_apps()

    assert :crypto in result
    assert :elixir in result
    assert :file_system in result
    assert :hologram in result
  end

  describe "module_beam_defs/1" do
    test "with debug info present in the BEAM file" do
      assert module_beam_defs(Module1) == [
               {{:fun_2, 2}, :def, [line: 7],
                [
                  {[line: 7],
                   [{:a, [version: 0, line: 7], nil}, {:b, [version: 1, line: 7], nil}], [],
                   {{:., [line: 8], [:erlang, :+]}, [line: 8],
                    [{:a, [version: 0, line: 8], nil}, {:b, [version: 1, line: 8], nil}]}}
                ]},
               {{:fun_1, 0}, :def, [line: 3], [{[line: 3], [], [], :value_1}]}
             ]
    end

    test "with debug info not present in the BEAM file" do
      assert module_beam_defs(Elixir.Hex) == []
    end
  end

  describe "page?" do
    test "is a page module" do
      assert page?(Module2)
    end

    test "is not a module" do
      refute page?(123)
    end

    test "is not a page module" do
      refute page?(__MODULE__)
    end
  end

  test "root_path/0" do
    assert root_path() == File.cwd!()
  end

  test "root_priv_path/0" do
    assert root_priv_path() == File.cwd!() <> "/priv/hologram"
  end
end
