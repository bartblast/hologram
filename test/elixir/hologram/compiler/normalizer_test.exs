defmodule Hologram.Compiler.NormalizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Normalizer

  describe "alias (__aliases__)" do
    test "3rd tuple elem is a list of atoms" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert normalize(ast) == ast
    end

    test "3rd tuple elem is a module" do
      ast = {:__aliases__, [line: 1], [Aaa.Bbb]}
      assert normalize(ast) == {:__aliases__, [line: 1], [:Aaa, :Bbb]}
    end
  end

  describe "atom" do
    test "module" do
      assert normalize(Aaa.Bbb) == {:__aliases__, [alias: false], [:Aaa, :Bbb]}
    end

    test "non-module" do
      # :abc
      assert normalize(:abc) == :abc
    end
  end

  describe "-> clause" do
    test "single expression block" do
      # Aaa -> Bbb
      ast = {:->, [line: 1], [[Aaa], Bbb]}

      assert normalize(ast) ==
               {:->, [line: 1],
                [
                  [{:__aliases__, [alias: false], [:Aaa]}],
                  {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                ]}
    end

    test "multiple expression block" do
      # Aaa ->
      #   Bbb
      #   Ccc
      ast = {:->, [line: 1], [[Aaa], {:__block__, [], [Bbb, Ccc]}]}

      assert normalize(ast) ==
               {:->, [line: 1],
                [
                  [{:__aliases__, [alias: false], [:Aaa]}],
                  {:__block__, [],
                   [
                     {:__aliases__, [alias: false], [:Bbb]},
                     {:__aliases__, [alias: false], [:Ccc]}
                   ]}
                ]}
    end

    test "with guard" do
      # Aaa when Bbb -> Ccc
      ast = {:->, [line: 1], [[{:when, [line: 1], [Aaa, Bbb]}], Ccc]}

      assert normalize(ast) ==
               {:->, [line: 1],
                [
                  [
                    {:when, [line: 1],
                     [
                       {:__aliases__, [alias: false], [:Aaa]},
                       {:__aliases__, [alias: false], [:Bbb]}
                     ]}
                  ],
                  {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                ]}
    end
  end

  describe "<- clause" do
    test "without guard" do
      # Aaa <- Bbb
      ast = {:<-, [line: 1], [Aaa, Bbb]}

      assert normalize(ast) ==
               {:<-, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  {:__aliases__, [alias: false], [:Bbb]}
                ]}
    end

    test "with guard" do
      # Aaa when Bbb <- Ccc
      ast =
        {:<-, [line: 1],
         [
           {:when, [line: 1], [Aaa, Bbb]},
           Ccc
         ]}

      assert normalize(ast) ==
               {:<-, [line: 1],
                [
                  {:when, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     {:__aliases__, [alias: false], [:Bbb]}
                   ]},
                  {:__aliases__, [alias: false], [:Ccc]}
                ]}
    end
  end

  describe "case" do
    test "single clause" do
      # case Aaa do
      #   Bbb -> Ccc
      # end
      ast = {:case, [line: 1], [Aaa, [do: [{:->, [line: 2], [[Bbb], Ccc]}]]]}

      assert normalize(ast) ==
               {:case, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [
                    do: [
                      {:->, [line: 2],
                       [
                         [{:__aliases__, [alias: false], [:Bbb]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "multiple clauses" do
      # case Aaa do
      #   Bbb -> Ccc
      #   Ddd -> Eee
      # end
      ast =
        {:case, [line: 1],
         [
           Aaa,
           [
             do: [
               {:->, [line: 2], [[Bbb], Ccc]},
               {:->, [line: 3], [[Ddd], Eee]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:case, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [
                    do: [
                      {:->, [line: 2],
                       [
                         [{:__aliases__, [alias: false], [:Bbb]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]},
                      {:->, [line: 3],
                       [
                         [{:__aliases__, [alias: false], [:Ddd]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}
                       ]}
                    ]
                  ]
                ]}
    end
  end

  describe "comprehension" do
    test "single expression mapper" do
      # for x <- [1, 2], do: Aaa
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              {:x, [line: 1], nil},
              [1, 2]
            ]},
           [do: Aaa]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:x, [line: 1], nil},
                     [
                       1,
                       2
                     ]
                   ]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]}]
                ]}
    end

    test "multiple expressions mapper" do
      # for x <- [1, 2] do
      #   Aaa
      #   Bbb
      # end
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              {:x, [line: 1], nil},
              [1, 2]
            ]},
           [
             do: {:__block__, [], [Aaa, Bbb]}
           ]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:x, [line: 1], nil},
                     [
                       1,
                       2
                     ]
                   ]},
                  [
                    do:
                      {:__block__, [],
                       [
                         {:__aliases__, [alias: false], [:Aaa]},
                         {:__aliases__, [alias: false], [:Bbb]}
                       ]}
                  ]
                ]}
    end

    test "generator enumerable" do
      # for x <- [Aaa, Bbb], do: 1
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              {:x, [line: 1], nil},
              [Aaa, Bbb]
            ]},
           [do: 1]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:x, [line: 1], nil},
                     [
                       {:__aliases__, [alias: false], [:Aaa]},
                       {:__aliases__, [alias: false], [:Bbb]}
                     ]
                   ]},
                  [do: {:__block__, [], [1]}]
                ]}
    end

    test "generator match" do
      # for Aaa <- [1, 2], do: 3
      ast = {:for, [line: 1], [{:<-, [line: 1], [Aaa, [1, 2]]}, [do: 3]]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:__aliases__, [alias: false], [:Aaa]}, [1, 2]]},
                  [do: {:__block__, [], [3]}]
                ]}
    end

    test "generator guard" do
      # for Aaa when Bbb <- [Ccc, Ddd], do: 1
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              {:when, [line: 1], [Aaa, Bbb]},
              [Ccc, Ddd]
            ]},
           [do: 1]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:when, [line: 1],
                      [
                        {:__aliases__, [alias: false], [:Aaa]},
                        {:__aliases__, [alias: false], [:Bbb]}
                      ]},
                     [
                       {:__aliases__, [alias: false], [:Ccc]},
                       {:__aliases__, [alias: false], [:Ddd]}
                     ]
                   ]},
                  [do: {:__block__, [], [1]}]
                ]}
    end

    test "single generator" do
      # for Aaa <- [Bbb, Ccc], do: 1
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              Aaa,
              [Bbb, Ccc]
            ]},
           [do: 1]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     [
                       {:__aliases__, [alias: false], [:Bbb]},
                       {:__aliases__, [alias: false], [:Ccc]}
                     ]
                   ]},
                  [do: {:__block__, [], [1]}]
                ]}
    end

    test "multiple generators" do
      # for Aaa <- [Bbb, Ccc], Ddd <- [Eee, Fff], do: 1
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              Aaa,
              [Bbb, Ccc]
            ]},
           {:<-, [line: 1],
            [
              Ddd,
              [Eee, Fff]
            ]},
           [do: 1]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     [
                       {:__aliases__, [alias: false], [:Bbb]},
                       {:__aliases__, [alias: false], [:Ccc]}
                     ]
                   ]},
                  {:<-, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Ddd]},
                     [
                       {:__aliases__, [alias: false], [:Eee]},
                       {:__aliases__, [alias: false], [:Fff]}
                     ]
                   ]},
                  [do: {:__block__, [], [1]}]
                ]}
    end

    test "single filter" do
      # for x <- [1, 2], Aaa, do: 3
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           Aaa,
           [do: 3]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  {:__aliases__, [alias: false], [:Aaa]},
                  [do: {:__block__, [], [3]}]
                ]}
    end

    test "multiple filters" do
      # for x <- [1, 2], Aaa, Bbb, do: 3
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           Aaa,
           Bbb,
           [do: 3]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  {:__aliases__, [alias: false], [:Aaa]},
                  {:__aliases__, [alias: false], [:Bbb]},
                  [do: {:__block__, [], [3]}]
                ]}
    end

    test "collectable opt" do
      # for x <- [1, 2], into: Aaa, do: 3
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           [into: Aaa, do: 3]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  [into: {:__aliases__, [alias: false], [:Aaa]}, do: {:__block__, [], [3]}]
                ]}
    end

    test "unique opt" do
      # for x <- [1, 2], uniq: Aaa, do: 3
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           [uniq: Aaa, do: 3]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  [uniq: {:__aliases__, [alias: false], [:Aaa]}, do: {:__block__, [], [3]}]
                ]}
    end

    test "reducer with single clause" do
      # for x <- [1, 2], reduce: Aaa do
      #   Bbb -> Ccc
      # end
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           [reduce: Aaa],
           [
             do: [
               {:->, [line: 2], [[Bbb], Ccc]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  [reduce: {:__aliases__, [alias: false], [:Aaa]}],
                  [
                    do:
                      {:__block__, [],
                       [
                         [
                           {:->, [line: 2],
                            [
                              [{:__aliases__, [alias: false], [:Bbb]}],
                              {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                            ]}
                         ]
                       ]}
                  ]
                ]}
    end

    test "reducer with multiple clauses" do
      # for x <- [1, 2], reduce: Aaa do
      #   Bbb -> Ccc
      #   Ddd -> Eee
      # end
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           [reduce: Aaa],
           [
             do: [
               {:->, [line: 2], [[Bbb], Ccc]},
               {:->, [line: 3], [[Ddd], Eee]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  [reduce: {:__aliases__, [alias: false], [:Aaa]}],
                  [
                    do:
                      {:__block__, [],
                       [
                         [
                           {:->, [line: 2],
                            [
                              [{:__aliases__, [alias: false], [:Bbb]}],
                              {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                            ]},
                           {:->, [line: 3],
                            [
                              [{:__aliases__, [alias: false], [:Ddd]}],
                              {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}
                            ]}
                         ]
                       ]}
                  ]
                ]}
    end

    test "reducer clause with guard" do
      # for x <- [1, 2], reduce: Aaa do
      #   Bbb when Ccc -> Ddd
      # end
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
           [reduce: Aaa],
           [
             do: [
               {:->, [line: 2],
                [
                  [
                    {:when, [line: 2],
                     [
                       Bbb,
                       Ccc
                     ]}
                  ],
                  Ddd
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:for, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, [1, 2]]},
                  [reduce: {:__aliases__, [alias: false], [:Aaa]}],
                  [
                    do:
                      {:__block__, [],
                       [
                         [
                           {:->, [line: 2],
                            [
                              [
                                {:when, [line: 2],
                                 [
                                   {:__aliases__, [alias: false], [:Bbb]},
                                   {:__aliases__, [alias: false], [:Ccc]}
                                 ]}
                              ],
                              {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                            ]}
                         ]
                       ]}
                  ]
                ]}
    end
  end

  describe "cond" do
    test "single clause" do
      # cond do
      #   Aaa -> Bbb
      # end
      ast = {:cond, [line: 1], [[do: [{:->, [line: 2], [[Aaa], Bbb]}]]]}

      assert normalize(ast) ==
               {:cond, [line: 1],
                [
                  [
                    do: [
                      {:->, [line: 2],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "multiple clauses" do
      # cond do
      #   Aaa -> Bbb
      #   Ccc -> Ddd
      # end
      ast =
        {:cond, [line: 1],
         [
           [
             do: [
               {:->, [line: 2], [[Aaa], Bbb]},
               {:->, [line: 3], [[Ccc], Ddd]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:cond, [line: 1],
                [
                  [
                    do: [
                      {:->, [line: 2],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]},
                      {:->, [line: 3],
                       [
                         [{:__aliases__, [alias: false], [:Ccc]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                       ]}
                    ]
                  ]
                ]}
    end
  end

  describe "def" do
    test "single expression block" do
      # def my_fun, do: Aaa
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: Aaa]]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:my_fun, [line: 1], nil},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]}]
                ]}
    end

    test "multiple expressions block" do
      # def my_fun do
      #   Aaa
      #   Bbb
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], [Aaa, Bbb]}]]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:my_fun, [line: 1], nil},
                  [
                    do:
                      {:__block__, [],
                       [
                         {:__aliases__, [alias: false], [:Aaa]},
                         {:__aliases__, [alias: false], [:Bbb]}
                       ]}
                  ]
                ]}
    end
  end

  describe "defp" do
    test "single expression block" do
      # defp my_fun, do: Aaa
      ast = {:defp, [line: 1], [{:my_fun, [line: 1], nil}, [do: Aaa]]}

      assert normalize(ast) ==
               {:defp, [line: 1],
                [
                  {:my_fun, [line: 1], nil},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]}]
                ]}
    end

    test "multiple expressions block" do
      # defp my_fun do
      #   Aaa
      #   Bbb
      # end
      ast = {:defp, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], [Aaa, Bbb]}]]}

      assert normalize(ast) ==
               {:defp, [line: 1],
                [
                  {:my_fun, [line: 1], nil},
                  [
                    do:
                      {:__block__, [],
                       [
                         {:__aliases__, [alias: false], [:Aaa]},
                         {:__aliases__, [alias: false], [:Bbb]}
                       ]}
                  ]
                ]}
    end
  end

  describe "defmodule" do
    test "single expression body" do
      # defmodule MyModule do
      #   Aaa
      # end
      ast =
        {:defmodule, [line: 1],
         [
           {:__aliases__, [line: 1], [:MyModule]},
           [do: Aaa]
         ]}

      assert normalize(ast) ==
               {:defmodule, [line: 1],
                [
                  {:__aliases__, [line: 1], [:MyModule]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]}]
                ]}
    end

    test "multiple expressions body" do
      # defmodule MyModule do
      #   Aaa
      #   Bbb
      # end
      ast =
        {:defmodule, [line: 1],
         [
           {:__aliases__, [line: 1], [:MyModule]},
           [
             do: {:__block__, [], [Aaa, Bbb]}
           ]
         ]}

      assert normalize(ast) ==
               {:defmodule, [line: 1],
                [
                  {:__aliases__, [line: 1], [:MyModule]},
                  [
                    do:
                      {:__block__, [],
                       [
                         {:__aliases__, [alias: false], [:Aaa]},
                         {:__aliases__, [alias: false], [:Bbb]}
                       ]}
                  ]
                ]}
    end
  end

  test "unquote" do
    ast = {{:unquote, [], [:%]}, [line: 1], [Aaa, Bbb]}

    assert normalize(ast) ==
             {:%, [line: 1],
              [
                {:__aliases__, [alias: false], [:Aaa]},
                {:__aliases__, [alias: false], [:Bbb]}
              ]}
  end

  test "list" do
    ast = [Aaa, Bbb, Ccc]

    assert normalize(ast) == [
             {:__aliases__, [alias: false], [:Aaa]},
             {:__aliases__, [alias: false], [:Bbb]},
             {:__aliases__, [alias: false], [:Ccc]}
           ]
  end

  test "tuple" do
    ast = {Aaa, Bbb, Ccc}

    assert normalize(ast) == {
             {:__aliases__, [alias: false], [:Aaa]},
             {:__aliases__, [alias: false], [:Bbb]},
             {:__aliases__, [alias: false], [:Ccc]}
           }
  end

  test "keyword with :do key" do
    # [do: Aaa]
    ast = [do: Aaa]

    assert normalize(ast) == [do: {:__aliases__, [alias: false], [:Aaa]}]
  end

  test "for variable" do
    # for
    ast = {:for, [line: 1], nil}

    assert normalize(ast) == ast
  end
end
