defmodule Hologram.Compiler.ProcessorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.Processor

  describe "aliases" do
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

  # TODO: attributes, functions, imports, name
end
