defmodule Hologram.Compiler.ModuleTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.AST.{Alias, Function, Import, IntegerType, Module, ModuleAttributeDef}
  alias Hologram.Compiler.ModuleTransformer

  test "name" do
    code = """
    defmodule Abc.Bcd do
    end
    """

    ast = ast(code)

    assert %Module{name: [:Abc, :Bcd]} = ModuleTransformer.transform(ast)
  end

  test "macros expansion" do
    code = """
    defmodule Abc do
      use Hologram.Test.Fixtures.Compiler.ModuleTransformer.Module2
    end
    """

    ast = ast(code)
    assert %Module{} = result = ModuleTransformer.transform(ast)

    expected = [
      %Import{
        module: [:Hologram, :Test, :Fixtures, :Compiler, :ModuleTransformer, :Module1],
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
    assert %Module{} = result = ModuleTransformer.transform(ast)

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
    assert %Module{} = result = ModuleTransformer.transform(ast)

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
    assert %Module{} = result = ModuleTransformer.transform(ast)

    expected = [
      %ModuleAttributeDef{
        name: :x,
        value: %IntegerType{value: 1}
      },
      %ModuleAttributeDef{
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
    assert %Module{} = result = ModuleTransformer.transform(ast)

    expected = [
      %Function{
        arity: 0,
        bindings: [],
        body: [%IntegerType{value: 1}],
        name: :test_1,
        params: []
      },
      %Function{
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
