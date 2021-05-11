defmodule Hologram.Compiler.NormalizerTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Parser

  test "do expression with non-nested block" do
    code = """
    defmodule Test do
      def test do
        1
      end
    end
    """

    ast = Parser.parse!(code)

    result = Normalizer.normalize(ast)

    expected =
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

    assert result == expected
  end

  test "do expression with nested block" do
    code = """
    defmodule Test do
      def test do
        nested do
          1
        end
      end
    end
    """

    ast = Parser.parse!(code)

    result = Normalizer.normalize(ast)

    expected =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [
                {:def, [line: 2],
                [
                  {:test, [line: 2], nil},
                  [
                    do: {:__block__, [],
                      [{:nested, [line: 3], [[do: {:__block__, [], [1]}]]}]}
                  ]
                ]}
              ]}
          ]
        ]}

    assert result == expected
  end

  test "do expression without block" do
    code = """
    defmodule Test do
      alias Abc
    end
    """

    ast = Parser.parse!(code)

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

  test "other expression" do
    code = "1 + 2"
    ast = Parser.parse!(code)
    
    result = Normalizer.normalize(ast)
    assert result == ast
  end
end
