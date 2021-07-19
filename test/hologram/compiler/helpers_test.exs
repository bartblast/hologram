defmodule Hologram.Compiler.HelpersTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.{ModuleDefinition, UseDirective}

  test "class_name/1" do
    assert Helpers.class_name([:Abc, :Bcd]) == "AbcBcd"
  end

  describe "is_component?/1" do
    test "true" do
      module_definition = %ModuleDefinition{
        uses: [
          %UseDirective{
            module: [:Hologram, :Component]
          }
        ]
      }

      assert Helpers.is_component?(module_definition)
    end

    test "false" do
      module_definition = %ModuleDefinition{uses: []}
      refute Helpers.is_component?(module_definition)
    end
  end

  describe "is_page?/1" do
    test "true" do
      module_definition = %ModuleDefinition{
        uses: [
          %UseDirective{
            module: [:Hologram, :Page]
          }
        ]
      }

      assert Helpers.is_page?(module_definition)
    end

    test "false" do
      module_definition = %ModuleDefinition{uses: []}
      refute Helpers.is_page?(module_definition)
    end
  end

  test "module/1" do
    result = Helpers.module([:Hologram, :Compiler, :HelpersTest])
    expected = Elixir.Hologram.Compiler.HelpersTest
    assert result == expected
  end

  test "module_name/1" do
    assert Helpers.module_name([:Abc, :Bcd]) == "Abc.Bcd"
  end

  test "module_name_atom/1" do
    assert Helpers.module_name_atom([:Abc, :Bcd]) == :"Abc.Bcd"
  end

  describe "module_name_segments/1" do
    test "string param" do
      assert Helpers.module_name_segments("Abc.Bcd") == [:Abc, :Bcd]
    end

    test "module param" do
      assert Helpers.module_name_segments(Abc.Bcd) == [:Abc, :Bcd]
    end
  end

  test "module_source_path/1" do
    result = Helpers.module_source_path(Hologram.Compiler.HelpersTest)
    expected = __ENV__.file

    assert result == expected
  end

  describe "uses_module?/2" do
    @used_module [:Hologram, :Commons, :Parser]

    test "true" do
      user_module = %ModuleDefinition{
        uses: [
          %UseDirective{
            module: @used_module
          }
        ]
      }

      assert Helpers.uses_module?(user_module, @used_module)
    end

    test "false" do
      user_module = %ModuleDefinition{uses: []}
      refute Helpers.uses_module?(user_module, @used_module)
    end
  end
end
