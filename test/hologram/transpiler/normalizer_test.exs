defmodule Hologram.Transpiler.NormalizerTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Normalizer

  test "do expression with block" do
    # AST from:
    #
    # defmodule Test do
    #   alias Abc

    #   def test do
    #     1
    #   end
    # end

    ast = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
          [
            {:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]},
            {:def, [line: 4], [{:test, [line: 4], nil}, [do: 1]]}
          ]}
        ]
      ]}

    result = Normalizer.normalize(ast)
    assert result == ast
  end

  test "do expression without block" do
    # AST from:
    #
    # defmodule Test do
    #   alias Abc
    # end

    ast =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [do: {:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]}]
        ]}

    result = Normalizer.normalize(ast)

    expected =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [{:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]}]}
          ]
        ]}

    assert result == expected
  end
end
