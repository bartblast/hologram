defmodule Hologram.Compiler.NormalizerTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.{Normalizer, Parser}

  describe "anonymous function" do
    test "arrow syntax" do
      code = "fn x -> x end"

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:fn, [line: 1],
         [
           {:->, [line: 1], [[{:x, [line: 1], nil}], {:__block__, [], [{:x, [line: 1], nil}]}]}
         ]}

      assert result == expected
    end

    # TODO: shorthand syntax
  end

  describe "case expression" do
    test "clause with single expression" do
      code = """
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
               {:->, [line: 2], [[1], {:__block__, [], [:expr]}]}
             ]
           ]
         ]}

      assert result == expected
    end

    test "clause with multiple expressions" do
      code = """
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

  describe "do param" do
    test "single expression in do block" do
      code = """
      test do
        :ok
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected = {:test, [line: 1], [[do: {:__block__, [], [:ok]}]]}

      assert result == expected
    end

    test "single expression in do keyword" do
      code = "test do: :ok"

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected = {:test, [line: 1], [[do: {:__block__, [], [:ok]}]]}

      assert result == expected
    end

    test "multiple expressions" do
      code = """
      test do
        1
        2
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected = {:test, [line: 1], [[do: {:__block__, [], [1, 2]}]]}

      assert result == expected
    end
  end

  describe "function definition" do
    test "single expression in do block" do
      code = """
      def test do
        :ok
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected = {:def, [line: 1], [{:test, [line: 1], nil}, [do: {:__block__, [], [:ok]}]]}

      assert result == expected
    end

    test "single expression in do keyword" do
      code = "def test, do: :ok"
      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected = {:def, [line: 1], [{:test, [line: 1], nil}, [do: {:__block__, [], [:ok]}]]}

      assert result == expected
    end

    test "multiple expressions" do
      code = """
      def test do
        1
        2
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected = {:def, [line: 1], [{:test, [line: 1], nil}, [do: {:__block__, [], [1, 2]}]]}

      assert result == expected
    end
  end

  describe "if expression" do
    test "standard notation if block with single expression without else block" do
      code = """
      if true do
        1
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [nil]}]]}

      assert result == expected
    end

    test "standard notation if block with single expression and else block with single expression" do
      code = """
      if true do
        1
      else
        2
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [2]}]]}

      assert result == expected
    end

    test "standard notation if block with single expression and else block with multiple expressions" do
      code = """
      if true do
        1
      else
        2
        3
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [2, 3]}]]}

      assert result == expected
    end

    test "standard notation if block with multiple expressions without else block" do
      code = """
      if true do
        1
        2
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [nil]}]]}

      assert result == expected
    end

    test "standard notation if block with multiple expressions and else block with single expression" do
      code = """
      if true do
        1
        2
      else
        3
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3]}]]}

      assert result == expected
    end

    test "standard notation if block with multiple expressions and else block with multiple expressions" do
      code = """
      if true do
        1
        2
      else
        3
        4
      end
      """

      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3, 4]}]]}

      assert result == expected
    end

    test "shorthand notation if block without else block" do
      code = "if true, do: 1"
      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [nil]}]]}

      assert result == expected
    end

    test "shorhand notation if block with else block" do
      code = "if true, do: 1, else: 2"
      ast = Parser.parse!(code)
      result = Normalizer.normalize(ast)

      expected =
        {:if, [line: 1], [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [2]}]]}

      assert result == expected
    end
  end

  test "other types of expressions" do
    code = "1 + 2"
    ast = Parser.parse!(code)
    result = Normalizer.normalize(ast)

    assert result == ast
  end
end
