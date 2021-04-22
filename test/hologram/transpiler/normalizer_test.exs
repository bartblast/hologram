defmodule Hologram.Transpiler.NormalizerTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Normalizer

  test "do expression with non-nested block" do
    # AST from:
    #
    # defmodule Test do
    #   alias Abc

    #   def test do
    #     1
    #   end
    # end

    ast =
      {:defmodule, [line: 1],
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

    expected =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
            [
              {:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]},
              {:def, [line: 4],
              [{:test, [line: 4], nil}, [do: {:__block__, [], [1]}]]}
            ]}
        ]
      ]}

    assert result == expected
  end

  test "do expression with nested block" do
    # AST from:
    #
    # defmodule Test do
    #   alias Abc

    #   def test do
    #     nested do
    #       1
    #     end
    #   end
    # end

    ast =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
            [
              {:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]},
              {:def, [line: 4],
              [{:test, [line: 4], nil}, [do: {:nested, [line: 5], [[do: 1]]}]]}
            ]}
        ]
      ]}

    result = Normalizer.normalize(ast)

    expected =
      {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
            [
              {:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]},
              {:def, [line: 4],
              [
                {:test, [line: 4], nil},
                [
                  do: {:__block__, [],
                    [{:nested, [line: 5], [[do: {:__block__, [], [1]}]]}]}
                ]
              ]}
            ]}
        ]
      ]}

    assert result = expected
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
