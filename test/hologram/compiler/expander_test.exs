defmodule Hologram.Compiler.ExpanderTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.Expander
  alias TestModule1
  alias TestModule2
  alias TestModule3
  alias TestModule5

  test "no use directives" do
    # normalized AST from:
    #
    # defmodule Test do
    #   def test do
    #       1
    #   end
    # end

    ast =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
          [
            {:def, [line: 2],
              [{:test, [line: 2], nil}, [do: {:__block__, [], [1]}]]}
          ]}
        ]
      ]}

    result = Expander.expand(ast)

    assert result == ast
  end

  test "single use directive" do
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

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
            [{:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]}]}
        ]
      ]}

    assert result == expected
  end

  test "multiple use directives" do
    # normalized AST from:
    #
    # defmodule Test do
    #   use TestModule2
    #   use TestModule4
    # end

    ast =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
           [
             {:use, [line: 2], [{:__aliases__, [line: 2], [:TestModule2]}]},
             {:use, [line: 3], [{:__aliases__, [line: 3], [:TestModule4]}]}
           ]}
        ]
      ]}

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
           [
             {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]},
             {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule3]}]}
           ]}
        ]
      ]}

    assert result == expected
  end

  test "single quote at the root of __using__ macro with a single expression" do
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

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
            [{:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]}]}
        ]
      ]}

    assert result == expected
  end

  test "single quote at the root of __using__ macro with multiple expressions" do
    # normalized AST from:
    #
    # defmodule Test do
    #   use TestModule5
    # end

    ast =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [{:use, [line: 2], [{:__aliases__, [line: 2], [:TestModule5]}]}]}
          ]
        ]}

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
            [
              {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]},
              {:import, [line: 5], [{:__aliases__, [line: 5], [:TestModule3]}]}
            ]
          }
        ]
      ]}

    assert result == expected
  end
end
