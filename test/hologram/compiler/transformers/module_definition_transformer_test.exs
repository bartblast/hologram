defmodule Hologram.Compiler.ModuleDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{Alias, FunctionDefinition, Import, IntegerType, ModuleDefinition, ModuleAttributeDefinition}
  alias Hologram.Compiler.ModuleDefinitionTransformer

  test "name" do
    code = """
    defmodule Abc.Bcd do
    end
    """

    ast = ast(code)

    assert %ModuleDefinition{name: [:Abc, :Bcd]} = ModuleDefinitionTransformer.transform(ast)
  end

  test "macros expansion" do
    code = """
    defmodule Abc do
      use Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %Import{
        module: [:Hologram, :Test, :Fixtures, :Compiler, :ModuleDefinitionTransformer, :Module1],
        only: nil
      }
    ]

    assert result.imports == expected
  end

  test "imports" do
    code = """
    defmodule Abc.Bcd do
      import Cde.Def
      import Efg.Fgh
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %Import{module: [:Cde, :Def], only: nil},
      %Import{module: [:Efg, :Fgh], only: nil}
    ]

    assert result.imports == expected
  end

  test "aliases" do
    code = """
    defmodule Abc.Bcd do
      alias Cde.Def
      alias Efg.Fgh
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %Alias{module: [:Cde, :Def], as: [:Def]},
      %Alias{module: [:Efg, :Fgh], as: [:Fgh]}
    ]

    assert result.aliases == expected
  end

  test "attributes" do
    code = """
    defmodule Abc do
      @x 1
      @y 2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %ModuleAttributeDefinition{
        name: :x,
        value: %IntegerType{value: 1}
      },
      %ModuleAttributeDefinition{
        name: :y,
        value: %IntegerType{value: 2}
      }
    ]

    assert result.attributes == expected
  end

  test "functions" do
    code = """
    defmodule Abc do
      def test_1 do
        1
      end

      def test_2 do
        2
      end
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %FunctionDefinition{
        arity: 0,
        bindings: [],
        body: [%IntegerType{value: 1}],
        name: :test_1,
        params: []
      },
      %FunctionDefinition{
        arity: 0,
        bindings: [],
        body: [%IntegerType{value: 2}],
        name: :test_2,
        params: []
      }
    ]

    assert result.functions == expected
  end
end
