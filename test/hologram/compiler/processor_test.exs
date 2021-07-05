defmodule Hologram.Compiler.ProcessorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{Alias, ModuleDefinition}
  alias Hologram.Compiler.Processor

  describe "compile/2, aliases" do
    test "no aliases" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module1]
      result = Processor.compile(module)

      assert result[module].aliases == []
    end

    test "non-nested alias" do
      module_2 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module2]
      module_1 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module1]

      result = Processor.compile(module_2)

      assert result[module_2].aliases == [%Alias{as: [:Module1], module: module_1}]
      assert result[module_1].aliases == []
    end

    test "nested alias" do
      module_5 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module5]
      module_2 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module2]
      module_1 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module1]

      result = Processor.compile(module_5)

      assert result[module_5].aliases == [%Alias{as: [:Module2], module: module_2}]
      assert result[module_2].aliases == [%Alias{as: [:Module1], module: module_1}]
      assert result[module_1].aliases == []
    end

    test "alias circular dependency" do
      module_3 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module3]
      module_4 = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module4]

      result = Processor.compile(module_3)

      assert result[module_3].aliases == [%Alias{as: [:Module4], module: module_4}]
      assert result[module_4].aliases == [%Alias{as: [:Module3], module: module_3}]
    end
  end

  describe "compile/2, components" do
    test "not a component" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module1]
      result = Processor.compile(module)

      assert Enum.count(result) == 1
      assert result[module]
    end

    test "component which doesn't use other components" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]
      result = Processor.compile(module)

      assert Enum.count(result) == 3
      assert result[module]
    end

    test "component which uses other non-aliased components" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module8]
      result = Processor.compile(module)

      assert Enum.count(result) == 5
      assert result[module]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module7]]
    end

    test "component which uses other aliased components" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module9]
      result = Processor.compile(module)

      assert Enum.count(result) == 5
      assert result[module]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module7]]
    end

    test "components nested in a component" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module10]
      result = Processor.compile(module)

      assert Enum.count(result) == 6
      assert result[module]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module7]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module9]]
    end

    test "handles element, text and expression nodes in component template" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module11]

      result = Processor.compile(module)
      assert result[module]
    end
  end

  describe "compile/2, pages" do
    test "not a page" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module1]
      result = Processor.compile(module)

      assert Enum.count(result) == 1
      assert result[module]
    end

    test "page which doesn't use other components" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module13]
      result = Processor.compile(module)

      assert Enum.count(result) == 3
      assert result[module]
    end

    test "page which uses other non-aliased components" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module14]
      result = Processor.compile(module)

      assert Enum.count(result) == 6
      assert result[module]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module7]]
    end

    test "page which uses other aliased components" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module15]
      result = Processor.compile(module)

      assert Enum.count(result) == 6
      assert result[module]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module7]]
    end

    test "components nested in a page" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module16]
      result = Processor.compile(module)

      assert Enum.count(result) == 7
      assert result[module]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module6]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module7]]
      assert result[[:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module9]]
    end

    test "handles element, text and expression nodes in page template" do
      module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module12]

      result = Processor.compile(module)
      assert result[module]
    end
  end

  test "get_module_definition/1" do
    module = [:Hologram, :Test, :Fixtures, :Compiler, :Processor, :Module1]
    assert %ModuleDefinition{} = Processor.get_module_definition(module)
  end

  # TODO: attributes, functions, imports, name
end
