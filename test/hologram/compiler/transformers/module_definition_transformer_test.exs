defmodule Hologram.Compiler.ModuleDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{
    AdditionOperator,
    Alias,
    AtomType,
    FunctionDefinition,
    Import,
    IntegerType,
    ListType,
    MacroDefinition,
    ModuleDefinition,
    ModuleAttributeDefinition,
    ModuleType,
    Quote,
    RequireDirective,
    TupleType,
    UseDirective,
    Variable
  }

  alias Hologram.Compiler.ModuleDefinitionTransformer

  @module_1 Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
  @module_2 Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
  @module_4 Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module4

  test "module" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1 do
    end
    """

    ast = ast(code)

    assert %ModuleDefinition{module: module} = ModuleDefinitionTransformer.transform(ast)
    assert module == @module_1
  end

  test "use directive expansion" do
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

  test "macro expansion" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      require Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module5
      test_macro(123)
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected =
      %FunctionDefinition{
        arity: 1,
        bindings: [b: {0, [%Variable{name: :b}]}],
        body: [
          %AdditionOperator{
            left: %IntegerType{value: 123},
            right: %Variable{name: :b}
          }
        ],
        name: :test_function,
        params: [%Variable{name: :b}]
      }

    assert Enum.member?(result.functions, expected)
  end

  test "__MODULE__ pseudo-variable expansion" do
    code = """
    defmodule Abc.Bcd do
      def test do
        __MODULE__
      end
    end
    """

    ast = ast(code)
    result = ModuleDefinitionTransformer.transform(ast)

    expected =
      %FunctionDefinition{
        arity: 0,
        bindings: [],
        body: [
          %ModuleType{module: Abc.Bcd}
        ],
        name: :test,
        params: []
      }

    assert Enum.member?(result.functions, expected)
  end

  test "uses" do
    code = """
    defmodule Hologram.Test.Fixtures.PlaceholderModule do
      use Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2
      use Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module4
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected = [
      %UseDirective{module: @module_2},
      %UseDirective{module: @module_4}
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

  test "multi-aliases" do
    code = """
    defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3 do
      alias Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.{Module1, Module2}
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

    expected_1 =
      %FunctionDefinition{
        arity: 0,
        bindings: [],
        body: [%IntegerType{value: 1}],
        name: :test_1,
        params: []
      }

    expected_2 =
      %FunctionDefinition{
        arity: 0,
        bindings: [],
        body: [%IntegerType{value: 2}],
        name: :test_2,
        params: []
      }

    assert Enum.count(result.functions) == 3
    assert Enum.member?(result.functions, expected_1)
    assert Enum.member?(result.functions, expected_2)
  end

  test "__info__/1 module callback injection" do
    code = """
    defmodule Hologram.Test.Fixtures.PlaceholderModule do
      def test_1, do: 1
      def test_2(x), do: 2
    end
    """

    ast = ast(code)
    assert %ModuleDefinition{} = result = ModuleDefinitionTransformer.transform(ast)

    expected =
      %FunctionDefinition{
        arity: 1,
        bindings: [],
        body: [
          %ListType{
            data: [
              %TupleType{
                data: [
                  %AtomType{value: :test_1},
                  %IntegerType{value: 0}
                ]
              },
              %TupleType{
                data: [
                  %AtomType{value: :test_2},
                  %IntegerType{value: 1}
                ]
              }
            ]
          }
        ],
        name: :__info__,
        params: [%AtomType{value: :functions}]
      }

    assert Enum.member?(result.functions, expected)
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
        module: @module_1,
        name: :test_1,
        arity: 0,
        body: [%Quote{body: [%IntegerType{value: 1}]}]
      },
      %MacroDefinition{
        module: @module_1,
        name: :test_2,
        arity: 0,
        body: [%Quote{body: [%IntegerType{value: 2}]}]
      }
    ]

    assert result.macros == expected
  end
end
