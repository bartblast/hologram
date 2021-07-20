defmodule Hologram.Compiler.ProcessorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{Alias, ModuleDefinition}
  alias Hologram.Compiler.Processor

  @module_1 Hologram.Test.Fixtures.Compiler.Processor.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.Processor.Module2
  @module_3 Hologram.Test.Fixtures.Compiler.Processor.Module3
  @module_4 Hologram.Test.Fixtures.Compiler.Processor.Module4
  @module_5 Hologram.Test.Fixtures.Compiler.Processor.Module5
  @module_6 Hologram.Test.Fixtures.Compiler.Processor.Module6
  @module_7 Hologram.Test.Fixtures.Compiler.Processor.Module7
  @module_8 Hologram.Test.Fixtures.Compiler.Processor.Module8
  @module_9 Hologram.Test.Fixtures.Compiler.Processor.Module9
  @module_10 Hologram.Test.Fixtures.Compiler.Processor.Module10
  @module_11 Hologram.Test.Fixtures.Compiler.Processor.Module11
  @module_12 Hologram.Test.Fixtures.Compiler.Processor.Module12
  @module_13 Hologram.Test.Fixtures.Compiler.Processor.Module13
  @module_14 Hologram.Test.Fixtures.Compiler.Processor.Module14
  @module_15 Hologram.Test.Fixtures.Compiler.Processor.Module15
  @module_16 Hologram.Test.Fixtures.Compiler.Processor.Module16

  describe "compile/2, aliases" do
    test "no aliases" do
      result = Processor.compile(@module_1)
      assert result[@module_1].aliases == []
    end

    test "non-nested alias" do
      result = Processor.compile(@module_2)

      assert result[@module_2].aliases == [%Alias{as: [:Module1], module: @module_1}]
      assert result[@module_1].aliases == []
    end

    test "nested alias" do
      result = Processor.compile(@module_5)

      assert result[@module_5].aliases == [%Alias{as: [:Module2], module: @module_2}]
      assert result[@module_2].aliases == [%Alias{as: [:Module1], module: @module_1}]
      assert result[@module_1].aliases == []
    end

    test "alias circular dependency" do
      result = Processor.compile(@module_3)

      assert result[@module_3].aliases == [%Alias{as: [:Module4], module: @module_4}]
      assert result[@module_4].aliases == [%Alias{as: [:Module3], module: @module_3}]
    end
  end

  describe "compile/2, components" do
    test "not a component" do
      result = Processor.compile(@module_1)

      assert Enum.count(result) == 1
      assert result[@module_1]
    end

    test "component which doesn't use other components" do
      result = Processor.compile(@module_6)

      assert Enum.count(result) == 3
      assert result[@module_6]
    end

    test "component which uses other non-aliased components" do
      result = Processor.compile(@module_8)

      assert Enum.count(result) == 5
      assert result[@module_6]
      assert result[@module_7]
      assert result[@module_8]
    end

    test "component which uses other aliased components" do
      result = Processor.compile(@module_9)

      assert Enum.count(result) == 5
      assert result[@module_6]
      assert result[@module_7]
      assert result[@module_9]
    end

    test "components nested in a component" do
      result = Processor.compile(@module_10)

      assert Enum.count(result) == 6
      assert result[@module_6]
      assert result[@module_7]
      assert result[@module_9]
      assert result[@module_10]
    end

    test "handles element, text and expression nodes in component template" do
      result = Processor.compile(@module_11)
      assert result[@module_11]
    end
  end

  describe "compile/2, pages" do
    test "not a page" do
      result = Processor.compile(@module_1)

      assert Enum.count(result) == 1
      assert result[@module_1]
    end

    test "page which doesn't use other components" do
      result = Processor.compile(@module_13)

      assert Enum.count(result) == 3
      assert result[@module_13]
    end

    test "page which uses other non-aliased components" do
      result = Processor.compile(@module_14)

      assert Enum.count(result) == 6
      assert result[@module_6]
      assert result[@module_7]
      assert result[@module_14]
    end

    test "page which uses other aliased components" do
      result = Processor.compile(@module_15)

      assert Enum.count(result) == 6
      assert result[@module_6]
      assert result[@module_7]
      assert result[@module_15]
    end

    test "components nested in a page" do
      result = Processor.compile(@module_16)

      assert Enum.count(result) == 7
      assert result[@module_6]
      assert result[@module_7]
      assert result[@module_9]
      assert result[@module_16]
    end

    test "handles element, text and expression nodes in page template" do
      result = Processor.compile(@module_12)
      assert result[@module_12]
    end
  end

  test "get_module_definition/1" do
    assert %ModuleDefinition{} = Processor.get_module_definition(@module_1)
  end

  # TODO: attributes, functions, imports, name
end
