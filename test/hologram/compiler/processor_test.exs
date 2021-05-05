defmodule Hologram.Compiler.ProcessorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.Alias
  alias Hologram.Compiler.Processor

  describe "aliases" do
    test "no aliases" do
      module_6 = [:TestModule6]

      result = Processor.compile(module_6)

      assert result[module_6].aliases == []
    end

    test "non-nested alias" do
      module_7 = [:TestModule7]
      module_6 = [:TestModule6]

      result = Processor.compile(module_7)

      assert result[module_7].aliases == [%Alias{as: module_6, module: module_6}]
      assert result[module_6].aliases == []
    end

    test "nested alias" do
      module_10 = [:TestModule10]
      module_7 = [:TestModule7]
      module_6 = [:TestModule6]

      result = Processor.compile(module_10)

      assert result[module_10].aliases == [%Alias{as: module_7, module: module_7}]
      assert result[module_7].aliases == [%Alias{as: module_6, module: module_6}]
      assert result[module_6].aliases == []
    end

    test "alias circular dependency" do
      module_8 = [:TestModule8]
      module_9 = [:TestModule9]

      result = Processor.compile(module_8)

      assert result[module_8].aliases == [%Alias{as: module_9, module: module_9}]
      assert result[module_9].aliases == [%Alias{as: module_8, module: module_8}]
    end
  end

  # TODO: attributes, functions, imports, name
end
