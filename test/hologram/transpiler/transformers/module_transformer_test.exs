defmodule Hologram.Transpiler.ModuleTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{Alias, Function, Import, IntegerType, Module, ModuleAttributeDef}
  alias Hologram.Transpiler.ModuleTransformer

  test "functions" do
    # normalized AST from:
    #
    # defmodule Abc.Bcd do
    #   def test_1 do
    #     1
    #   end

    #   def test_2 do
    #     2
    #   end
    # end

    ast =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Abc, :Bcd]},
          [
            do: {:__block__, [],
              [
                {:def, [line: 2],
                [{:test_1, [line: 2], nil}, [do: {:__block__, [], [1]}]]},
                {:def, [line: 6],
                [{:test_2, [line: 6], nil}, [do: {:__block__, [], [2]}]]}
              ]}
          ]
        ]}

    result = ModuleTransformer.transform(ast)

    expected =
      %Module{
        aliases: [],
        functions: [
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
        ],
        imports: [],
        name: [:Abc, :Bcd]
      }

    assert result == expected
  end

  test "aliases" do
    # normalized AST from:
    #
    # defmodule Abc.Bcd do
    #   alias Ghi.Hij
    #   alias Ijk.Jkl
    # end

    ast =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Abc, :Bcd]},
          [
            do: {:__block__, [],
              [
                {:alias, [line: 2], [{:__aliases__, [line: 2], [:Ghi, :Hij]}]},
                {:alias, [line: 3], [{:__aliases__, [line: 3], [:Ijk, :Jkl]}]}
              ]}
          ]
        ]}

    result = ModuleTransformer.transform(ast)

    expected =
      %Module{
        aliases: [
          %Alias{as: [:Hij], module: [:Ghi, :Hij]},
          %Alias{as: [:Jkl], module: [:Ijk, :Jkl]}
        ],
        functions: [],
        imports: [],
        name: [:Abc, :Bcd]
      }

    assert result == expected
  end

  test "imports" do
    # normalized AST from:
    #
    # defmodule Abc.Bcd do
    #   import Cde.Def
    #   import Efg.Fgh
    # end

    ast =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Abc, :Bcd]},
          [
            do: {:__block__, [],
              [
                {:import, [line: 2], [{:__aliases__, [line: 2], [:Cde, :Def]}]},
                {:import, [line: 3], [{:__aliases__, [line: 3], [:Efg, :Fgh]}]}
              ]}
          ]
        ]}

    result = ModuleTransformer.transform(ast)

    expected =
      %Module{
        aliases: [],
        functions: [],
        imports: [
          %Import{module: [:Cde, :Def], only: nil},
          %Import{module: [:Efg, :Fgh], only: nil}
        ],
        name: [:Abc, :Bcd]
      }

    assert result == expected
  end

  test "macro expansion" do
    # normalized AST from:
    #
    # defmodule Test do
    #   use TestModule2
    # end

    ast =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [{:use, [line: 2], [{:__aliases__, [line: 2], [:TestModule2]}]}]}
          ]
        ]}

    result = ModuleTransformer.transform(ast)

    expected =
      %Module{
        aliases: [],
        functions: [],
        imports: [%Import{module: [:TestModule1], only: nil}],
        name: [:Test]
      }

    assert result == expected
  end

  test "module attributes" do
    # normalized AST from:
    #
    # defmodule Abc.Bcd do
    #   @x 1
    #   @y 2
    # end

    ast =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Abc, :Bcd]},
        [
          do: {:__block__, [],
            [
              {:@, [line: 2], [{:x, [line: 2], [1]}]},
              {:@, [line: 3], [{:y, [line: 3], [2]}]}
            ]}
        ]
      ]}

    result = ModuleTransformer.transform(ast)

    expected =
      %Module{
        aliases: [],
        attributes: [
          %ModuleAttributeDef{
            name: :x,
            value: %IntegerType{value: 1}
          },
          %ModuleAttributeDef{
            name: :y,
            value: %IntegerType{value: 2}
          }
        ],
        functions: [],
        imports: [],
        name: [:Abc, :Bcd]
      }

    assert result == expected
  end
end
