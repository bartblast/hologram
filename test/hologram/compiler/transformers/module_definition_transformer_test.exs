defmodule Hologram.Compiler.ModuleDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{
    Alias,
    FunctionDefinition,
    Import,
    IntegerType,
    MacroDefinition,
    ModuleDefinition,
    ModuleAttributeDefinition,
    RequireDirective,
    UseDirective
  }

  alias Hologram.Compiler.ModuleDefinitionTransformer

  @module_1 Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2

  test "module" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1 do
    end
    """

    ast = ast(code)

    assert %ModuleDefinition{module: module} = ModuleDefinitionTransformer.transform(ast)
    assert module == @module_1
  end

  test "macros expansion" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      use Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %Import{
        module: @module_1,
        only: []
      }
    ]

    assert result.imports == expected
  end

  test "uses" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      use Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
      use Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %UseDirective{module: @module_1},
      %UseDirective{module: @module_2}
    ]

    assert result.uses == expected
  end

  test "imports" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      import Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
      import Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %Import{module: @module_1, only: []},
      %Import{module: @module_2, only: []}
    ]

    assert result.imports == expected
  end

  test "requires" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      require Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
      require Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %RequireDirective{module: @module_1},
      %RequireDirective{module: @module_2}
    ]

    assert result.requires == expected
  end

  test "aliases" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      alias Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
      alias Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %Alias{module: @module_1, as: [:Module1]},
      %Alias{module: @module_2, as: [:Module2]}
    ]

    assert result.aliases == expected
  end

  test "attributes" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1 do
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
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1 do
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

  test "macros" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1 do
      defmacro test_1 do
        quote do
          1
        end
      end

      defmacro test_2 do
        quote do
          2
        end
      end
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %MacroDefinition{
        arity: 0,
        bindings: [],
        body: [{:quote, [line: 3], [[do: {:__block__, [], [1]}]]}],
        name: :test_1,
        params: []
      },
      %MacroDefinition{
        arity: 0,
        bindings: [],
        body: [{:quote, [line: 9], [[do: {:__block__, [], [2]}]]}],
        name: :test_2,
        params: []
      }
    ]
  end
end
