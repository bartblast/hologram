defmodule Hologram.Compiler.NormalizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Normalizer

  describe "anonymous function" do
    test "arrow syntax" do
      # fn x -> x end
      ast = {:fn, [line: 1], [{:->, [line: 1], [[{:x, [line: 1], nil}], {:x, [line: 1], nil}]}]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
                  {:->, [line: 1],
                   [[{:x, [line: 1], nil}], {:__block__, [], [{:x, [line: 1], nil}]}]}
                ]}
    end

    # TODO: anonymous function shorthand syntax
  end

  describe "case expression" do
    test "clause with single expression" do
      # case x do
      #   1 ->
      #     :expr
      # end
      ast = {:case, [line: 1], [{:x, [line: 1], nil}, [do: [{:->, [line: 2], [[1], :expr]}]]]}

      assert normalize(ast) ==
               {:case, [line: 1],
                [
                  {:x, [line: 1], nil},
                  [
                    do: [
                      {:->, [line: 2], [[1], {:__block__, [], [:expr]}]}
                    ]
                  ]
                ]}
    end

    test "clause with multiple expressions" do
      # case x do
      #   1 ->
      #     :expr_a
      #     :expr_b
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [do: [{:->, [line: 2], [[1], {:__block__, [], [:expr_a, :expr_b]}]}]]
         ]}

      assert normalize(ast) ==
               {:case, [line: 1],
                [
                  {:x, [line: 1], nil},
                  [do: [{:->, [line: 2], [[1], {:__block__, [], [:expr_a, :expr_b]}]}]]
                ]}
    end
  end

  describe "do block" do
    test "single expression" do
      # abc do
      #   :ok
      # end
      #
      # (or)
      #
      # abc do: :ok
      ast = {:abc, [line: 1], [[do: :ok]]}

      assert normalize(ast) == {:abc, [line: 1], [[do: {:__block__, [], [:ok]}]]}
    end

    test "multiple expressions" do
      # abc do
      #   1
      #   2
      # end
      ast = {:abc, [line: 1], [[do: {:__block__, [], [1, 2]}]]}

      assert normalize(ast) == {:abc, [line: 1], [[do: {:__block__, [], [1, 2]}]]}
    end
  end

  describe "function definition" do
    test "single expression" do
      # def abc do
      #   :ok
      # end
      #
      # (or)
      #
      # def abc, do: :ok
      ast = {:def, [line: 1], [{:abc, [line: 1], nil}, [do: :ok]]}

      assert normalize(ast) ==
               {:def, [line: 1], [{:abc, [line: 1], nil}, [do: {:__block__, [], [:ok]}]]}
    end

    test "multiple expressions" do
      # def abc do
      #   1
      #   2
      # end
      ast = {:def, [line: 1], [{:abc, [line: 1], nil}, [do: {:__block__, [], [1, 2]}]]}

      assert normalize(ast) ==
               {:def, [line: 1], [{:abc, [line: 1], nil}, [do: {:__block__, [], [1, 2]}]]}
    end
  end

  describe "if expression" do
    test "single-expression if block without else block" do
      # if true do
      #   1
      # end
      #
      # (or)
      #
      # if true, do: 1
      ast = {:if, [line: 1], [true, [do: 1]]}

      assert normalize(ast) ==
               {:if, [line: 1],
                [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [nil]}]]}
    end

    test "single-expression if block with single-expression else block" do
      # if true do
      #   1
      # else
      #   2
      # end
      #
      # (or)
      #
      # if true, do: 1, else: 2
      ast = {:if, [line: 1], [true, [do: 1, else: 2]]}

      assert normalize(ast) ==
               {:if, [line: 1], [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [2]}]]}
    end

    test "single-expression if block with multiple-expression else block" do
      # if true do
      #   1
      # else
      #   2
      #   3
      # end
      ast = {:if, [line: 1], [true, [do: 1, else: {:__block__, [], [2, 3]}]]}

      assert normalize(ast) ==
               {:if, [line: 1],
                [true, [do: {:__block__, [], [1]}, else: {:__block__, [], [2, 3]}]]}
    end

    test "multiple-expression if block without else block" do
      # if true do
      #   1
      #   2
      # end
      ast = {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}]]}

      assert normalize(ast) ==
               {:if, [line: 1],
                [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [nil]}]]}
    end

    test "multiple-expression if block with single-expression else block" do
      # if true do
      #   1
      #   2
      # else
      #   3
      # end
      ast = {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: 3]]}

      assert normalize(ast) ==
               {:if, [line: 1],
                [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3]}]]}
    end

    test "multiple-expression if block with multiple-expression else block" do
      # if true do
      #   1
      #   2
      # else
      #   3
      #   4
      # end
      ast =
        {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3, 4]}]]}

      assert normalize(ast) ==
               {:if, [line: 1],
                [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3, 4]}]]}
    end
  end

  describe "atom" do
    test "alias" do
      assert normalize(A.B) == {:__aliases__, [alias: false], [:A, :B]}
    end

    test "non-alias" do
      assert normalize(:a) == :a
    end
  end

  test "fallback" do
    # 1 + 2
    ast = {:+, [line: 1], [1, 2]}

    assert normalize(ast) == ast
  end
end
