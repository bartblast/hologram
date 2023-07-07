defmodule Hologram.Compiler.NormalizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Normalizer

  describe "alias" do
    test "list of atoms" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert normalize(ast) == ast
    end

    test "module" do
      ast = {:__aliases__, [line: 1], [Aaa.Bbb]}
      assert normalize(ast) == {:__aliases__, [line: 1], [:Aaa, :Bbb]}
    end
  end

  test "anonymous function" do
    # fn x -> x end
    ast = {:fn, [line: 1], [{:->, [line: 1], [[{:x, [line: 1], nil}], {:x, [line: 1], nil}]}]}

    assert normalize(ast) ==
             {:fn, [line: 1],
              [
                {:->, [line: 1],
                 [[{:x, [line: 1], nil}], {:__block__, [], [{:x, [line: 1], nil}]}]}
              ]}
  end

  describe "case" do
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

      assert normalize(ast) == ast
    end
  end

  describe "cond" do
    test "clause with single expression" do
      # cond do
      #   1 ->
      #     :expr_a
      # end
      ast = {:cond, [], [[do: [{:->, [], [[1], :expr_a]}]]]}

      assert normalize(ast) ==
               {:cond, [], [[do: [{:->, [], [[1], {:__block__, [], [:expr_a]}]}]]]}
    end

    test "clause with multiple expressions" do
      # cond do
      #   1 ->
      #     :expr_a
      #     :expr_b
      # end
      ast = {:cond, [], [[do: [{:->, [], [[1], {:__block__, [], [:expr_a, :expr_b]}]}]]]}

      assert normalize(ast) == ast
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

      assert normalize(ast) == ast
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

      assert normalize(ast) == ast
    end
  end

  test "unquote" do
    ast =
      {{:unquote, [], [:%]}, [line: 69],
       [Dialyxir.FilterMap, {:%{}, [line: 69], [list_unused_filters?: true]}]}

    assert normalize(ast) ==
             {:%, [line: 69],
              [Dialyxir.FilterMap, {:%{}, [line: 69], [list_unused_filters?: true]}]}
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
