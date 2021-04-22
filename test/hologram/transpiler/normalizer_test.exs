defmodule Hologram.Transpiler.NormalizerTest do
  use ExUnit.Case, async: true
  import Hologram.Transpiler.Parser, only: [parse!: 1]
  alias Hologram.Transpiler.Normalizer

  test "module without block" do
    # AST from:
    # defmodule Test do
    #   def test do
    #     1
    #   end
    # end

    ast =
      {:defmodule, [line: 1], [
        {:__aliases__, [line: 1], [:Test]},
        [do: {:def, [line: 2], [{:test, [line: 2], nil}, [do: 1]]}]
      ]}

    result = Normalizer.normalize(ast)

    expected =
      {:defmodule, [line: 1], [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [], [
            {:def, [line: 2], [{:test, [line: 2], nil}, [do: 1]]}
          ]}
        ]
      ]}

    assert result == expected
  end

  test "module with block" do
    # AST from:
    # defmodule Test do
    #   alias Abc

    #   def test do
    #     1
    #   end
    # end

    ast =
      {:defmodule, [line: 1], [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [], [
            {:alias, [line: 2], [{:__aliases__, [line: 2], [:Abc]}]},
            {:def, [line: 4], [{:test, [line: 4], nil}, [do: 1]]}
          ]}
        ]
      ]}

    result = Normalizer.normalize(ast)
    assert result == ast
  end
end
