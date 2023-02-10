defmodule Hologram.Compiler.ModuleDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.Block
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.ModuleDefinitionTransformer

  test "empty body" do
    code = "defmodule Abc.Bcd do end"
    ast = ast(code)
    result = ModuleDefinitionTransformer.transform(ast)

    expected = %ModuleDefinition{
      module: %Alias{segments: [:Abc, :Bcd]},
      body: %Block{
        expressions: []
      }
    }
  end

  test "single expression body" do
    code = """
    defmodule Abc.Bcd do
      1
    end
    """

    ast = ast(code)
    result = ModuleDefinitionTransformer.transform(ast)

    expected = %ModuleDefinition{
      module: %Alias{segments: [:Abc, :Bcd]},
      body: %Block{
        expressions: [
          %IntegerType{value: 1}
        ]
      }
    }
  end

  test "multiple expressions body" do
    code = """
    defmodule Abc.Bcd do
      1
      2
    end
    """

    ast = ast(code)
    result = ModuleDefinitionTransformer.transform(ast)

    expected = %ModuleDefinition{
      module: %Alias{segments: [:Abc, :Bcd]},
      body: %Block{
        expressions: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]
      }
    }
  end
end
