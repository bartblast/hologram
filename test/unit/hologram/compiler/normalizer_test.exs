defmodule Hologram.Compiler.NormalizerTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.{Normalizer, Parser}

  describe "do expression" do
    test "without nested block" do
      code =
        """
        def test do
          :ok
        end
        """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:def, [line: 1], [{:test, [line: 1], nil}, [do: {:__block__, [], [:ok]}]]}

      assert result == expected
    end

    test "with nested block" do
      code =
        """
        def test do
          nested do
            1
          end
        end
        """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:def, [line: 1],
          [
            {:test, [line: 1], nil},
            [do: {:__block__, [], [{:nested, [line: 2], [[do: {:__block__, [], [1]}]]}]}]
          ]}

      assert result == expected
    end
  end

  describe "case expression" do
    test "clause with single expression" do
      code =
        """
        case x do
          1 ->
            :expr
        end
        """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:case, [line: 1],
          [
            {:x, [line: 1], nil},
            [
              do: [
                {:->, [line: 2], [[1], {:__block__, [], [:expr]}]},
              ]
            ]
          ]}

      assert result == expected
    end

    test "clause with block" do
      code =
        """
        case x do
          1 ->
            :expr_a
            :expr_b
        end
        """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:case, [line: 1],
          [
            {:x, [line: 1], nil},
            [do: [{:->, [line: 2], [[1], {:__block__, [], [:expr_a, :expr_b]}]}]]
          ]}

      assert result == expected
    end
  end

  test "other expression" do
    code = "1 + 2"
    ast = Parser.parse!(code)
    result = Normalizer.normalize(ast)

    assert result == ast
  end
end
