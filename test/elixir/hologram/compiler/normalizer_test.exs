defmodule Hologram.Compiler.NormalizerTest do
  @moduledoc """
  Fixture AST has module alias tuples replaced with module alias atoms,
  which allows to test whether that particular part of the AST is normalized as well.

  E.g.
  {:__aliases__, [line: 1], [:Aaa]}
  is replaced with:
  Aaa
  """

  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Normalizer

  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module1
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module10
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module11
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module12
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module13
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module14
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module15
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module16
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module2
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module3
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module4
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module5
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module6
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module7
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module8
  alias Hologram.Test.Fixtures.Compiler.Normalizer.Module9

  defp fetch_unnormalized_def_ast(module) do
    {:defmodule, _meta_1, [{:__aliases__, _meta_2, _args}, [do: {:__block__, [], [ast]}]]} =
      unnormalized_ast(module)

    ast
  end

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

  describe "anonymous function type" do
    test "single clause / clause with single expression body" do
      # fn Aaa -> Bbb end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1], [[Aaa], Bbb]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
                  {:->, [line: 1],
                   [
                     [{:__aliases__, [alias: false], [:Aaa]}],
                     {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                   ]}
                ]}
    end

    test "multiple clauses" do
      # fn
      #   Aaa -> Bbb
      #   Ccc -> Ddd
      # end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 2], [[Aaa], Bbb]},
           {:->, [line: 3], [[Ccc], Ddd]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
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
                ]}
    end

    test "clause with multiple expressions body" do
      # fn Aaa ->
      #   :expr_1
      #   :expr_2
      # end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [Aaa],
              {:__block__, [], [:expr_1, :expr_2]}
            ]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
                  {:->, [line: 1],
                   [
                     [{:__aliases__, [alias: false], [:Aaa]}],
                     {:__block__, [],
                      [
                        :expr_1,
                        :expr_2
                      ]}
                   ]}
                ]}
    end

    test "clause with single guard" do
      # fn Aaa when Bbb -> Ccc end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [
                {:when, [line: 1], [Aaa, Bbb]}
              ],
              Ccc
            ]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
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
                ]}
    end

    test "clause with multiple guards" do
      # fn Aaa when Bbb when Ccc when Ddd -> Eee end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [
                {:when, [line: 1],
                 [
                   Aaa,
                   {:when, [line: 1],
                    [
                      Bbb,
                      {:when, [line: 1],
                       [
                         Ccc,
                         Ddd
                       ]}
                    ]}
                 ]}
              ],
              Eee
            ]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
                  {:->, [line: 1],
                   [
                     [
                       {:when, [line: 1],
                        [
                          {:__aliases__, [alias: false], [:Aaa]},
                          {:when, [line: 1],
                           [
                             {:__aliases__, [alias: false], [:Bbb]},
                             {:when, [line: 1],
                              [
                                {:__aliases__, [alias: false], [:Ccc]},
                                {:__aliases__, [alias: false], [:Ddd]}
                              ]}
                           ]}
                        ]}
                     ],
                     {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}
                   ]}
                ]}
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

  describe "case" do
    test "single clause / clause with single expression body" do
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

    test "clause with multiple expressions body" do
      # case Aaa do
      #   Bbb ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:case, [line: 1],
         [
           Aaa,
           [
             do: [
               {:->, [line: 2],
                [
                  [Bbb],
                  {:__block__, [],
                   [
                     :expr_1,
                     :expr_2
                   ]}
                ]}
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
                         {:__block__, [],
                          [
                            :expr_1,
                            :expr_2
                          ]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "clause with single guard" do
      # case Aaa do
      #   Bbb when Ccc -> Ddd
      # end
      ast =
        {:case, [line: 1],
         [
           Aaa,
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
               {:case, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [
                    do: [
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
                  ]
                ]}
    end

    test "clause with multiple guards" do
      # case Aaa do
      #   Bbb when Ccc when Ddd when Eee -> Fff
      # end
      ast =
        {:case, [line: 1],
         [
           Aaa,
           [
             do: [
               {:->, [line: 2],
                [
                  [
                    {:when, [line: 2],
                     [
                       Bbb,
                       {:when, [line: 2],
                        [
                          Ccc,
                          {:when, [line: 2],
                           [
                             Ddd,
                             Eee
                           ]}
                        ]}
                     ]}
                  ],
                  Fff
                ]}
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
                         [
                           {:when, [line: 2],
                            [
                              {:__aliases__, [alias: false], [:Bbb]},
                              {:when, [line: 2],
                               [
                                 {:__aliases__, [alias: false], [:Ccc]},
                                 {:when, [line: 2],
                                  [
                                    {:__aliases__, [alias: false], [:Ddd]},
                                    {:__aliases__, [alias: false], [:Eee]}
                                  ]}
                               ]}
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Fff]}]}
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
      #   :expr_1
      #   :expr_2
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
             do: {:__block__, [], [:expr_1, :expr_2]}
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
                         :expr_1,
                         :expr_2
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

    test "generator with single guard" do
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

    test "generator with multiple guards" do
      # for Aaa when Bbb when Ccc when Ddd <- [Eee, Fff], do: 1
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1],
            [
              {:when, [line: 1],
               [
                 Aaa,
                 {:when, [line: 1],
                  [
                    Bbb,
                    {:when, [line: 1],
                     [
                       Ccc,
                       Ddd
                     ]}
                  ]}
               ]},
              [Eee, Fff]
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
                        {:when, [line: 1],
                         [
                           {:__aliases__, [alias: false], [:Bbb]},
                           {:when, [line: 1],
                            [
                              {:__aliases__, [alias: false], [:Ccc]},
                              {:__aliases__, [alias: false], [:Ddd]}
                            ]}
                         ]}
                      ]},
                     [
                       {:__aliases__, [alias: false], [:Eee]},
                       {:__aliases__, [alias: false], [:Fff]}
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

    test "reducer with single clause / clause with single expression body" do
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

    test "reducer clause with single guard" do
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

    test "reducer clause with multiple guards" do
      # for x <- [1, 2], reduce: Aaa do
      #   Bbb when Ccc when Ddd when Eee -> Fff
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
                       {:when, [line: 2],
                        [
                          Ccc,
                          {:when, [line: 2],
                           [
                             Ddd,
                             Eee
                           ]}
                        ]}
                     ]}
                  ],
                  Fff
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
                                   {:when, [line: 2],
                                    [
                                      {:__aliases__, [alias: false], [:Ccc]},
                                      {:when, [line: 2],
                                       [
                                         {:__aliases__, [alias: false], [:Ddd]},
                                         {:__aliases__, [alias: false], [:Eee]}
                                       ]}
                                    ]}
                                 ]}
                              ],
                              {:__block__, [], [{:__aliases__, [alias: false], [:Fff]}]}
                            ]}
                         ]
                       ]}
                  ]
                ]}
    end

    test "reducer clause with multiple expressions body" do
      # for x <- [1, 2], reduce: Aaa do
      #   Bbb ->
      #     :expr_1
      #     :expr_2
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
                  [Bbb],
                  {:__block__, [],
                   [
                     :expr_1,
                     :expr_2
                   ]}
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
                              [{:__aliases__, [alias: false], [:Bbb]}],
                              {:__block__, [],
                               [
                                 :expr_1,
                                 :expr_2
                               ]}
                            ]}
                         ]
                       ]}
                  ]
                ]}
    end
  end

  describe "cond" do
    test "single clause / clause with single expression body" do
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

    test "clause with multiple expressions body" do
      # cond do
      #   Aaa ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:cond, [line: 1],
         [
           [
             do: [
               {:->, [line: 2],
                [
                  [Aaa],
                  {:__block__, [],
                   [
                     :expr_1,
                     :expr_2
                   ]}
                ]}
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
                         {:__block__, [],
                          [
                            :expr_1,
                            :expr_2
                          ]}
                       ]}
                    ]
                  ]
                ]}
    end
  end

  describe "def" do
    test "single expression body" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # def Aaa, do: Bbb
      ast = {:def, [line: 1], [Aaa, [do: Bbb]]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}]
                ]}
    end

    test "multiple expressions body" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # def Aaa do
      #   :expr_1
      #   :expr_2
      # end
      ast =
        {:def, [line: 1],
         [
           Aaa,
           [
             do: {:__block__, [], [:expr_1, :expr_2]}
           ]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [
                    do:
                      {:__block__, [],
                       [
                         :expr_1,
                         :expr_2
                       ]}
                  ]
                ]}
    end

    test "single guard" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # def Aaa when Bbb, do: Ccc
      ast =
        {:def, [line: 1],
         [
           {:when, [line: 1], [Aaa, Bbb]},
           [do: Ccc]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:when, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     {:__aliases__, [alias: false], [:Bbb]}
                   ]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}]
                ]}
    end

    test "multiple guards" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # def Aaa when Bbb when Ccc when Ddd, do: Eee"
      ast =
        {:def, [line: 1],
         [
           {:when, [line: 1],
            [
              Aaa,
              {:when, [line: 1],
               [
                 Bbb,
                 {:when, [line: 1], [Ccc, Ddd]}
               ]}
            ]},
           [do: Eee]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:when, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     {:when, [line: 1],
                      [
                        {:__aliases__, [alias: false], [:Bbb]},
                        {:when, [line: 1],
                         [
                           {:__aliases__, [alias: false], [:Ccc]},
                           {:__aliases__, [alias: false], [:Ddd]}
                         ]}
                      ]}
                   ]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}]
                ]}
    end
  end

  describe "defp" do
    test "single expression body" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # defp Aaa, do: Bbb
      ast = {:defp, [line: 1], [Aaa, [do: Bbb]]}

      assert normalize(ast) ==
               {:defp, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}]
                ]}
    end

    test "multiple expressions body" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # defp Aaa do
      #   :expr_1
      #   :expr_2
      # end
      ast =
        {:defp, [line: 1],
         [
           Aaa,
           [
             do: {:__block__, [], [:expr_1, :expr_2]}
           ]
         ]}

      assert normalize(ast) ==
               {:defp, [line: 1],
                [
                  {:__aliases__, [alias: false], [:Aaa]},
                  [
                    do:
                      {:__block__, [],
                       [
                         :expr_1,
                         :expr_2
                       ]}
                  ]
                ]}
    end

    test "single guard" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # defp Aaa when Bbb, do: Ccc
      ast =
        {:defp, [line: 1],
         [
           {:when, [line: 1], [Aaa, Bbb]},
           [do: Ccc]
         ]}

      assert normalize(ast) ==
               {:defp, [line: 1],
                [
                  {:when, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     {:__aliases__, [alias: false], [:Bbb]}
                   ]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}]
                ]}
    end

    test "multiple guards" do
      # (this code is invalid, and the AST is made by hand for testing purposes only)
      # defp Aaa when Bbb when Ccc when Ddd, do: Eee"
      ast =
        {:defp, [line: 1],
         [
           {:when, [line: 1],
            [
              Aaa,
              {:when, [line: 1],
               [
                 Bbb,
                 {:when, [line: 1], [Ccc, Ddd]}
               ]}
            ]},
           [do: Eee]
         ]}

      assert normalize(ast) ==
               {:defp, [line: 1],
                [
                  {:when, [line: 1],
                   [
                     {:__aliases__, [alias: false], [:Aaa]},
                     {:when, [line: 1],
                      [
                        {:__aliases__, [alias: false], [:Bbb]},
                        {:when, [line: 1],
                         [
                           {:__aliases__, [alias: false], [:Ccc]},
                           {:__aliases__, [alias: false], [:Ddd]}
                         ]}
                      ]}
                   ]},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}]
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
      #   :expr_1
      #   :expr_2
      # end
      ast =
        {:defmodule, [line: 1],
         [
           {:__aliases__, [line: 1], [:MyModule]},
           [
             do: {:__block__, [], [:expr_1, :expr_2]}
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
                         :expr_1,
                         :expr_2
                       ]}
                  ]
                ]}
    end

    test "name" do
      # defmodule MyModule do
      #   1
      # end
      ast =
        {:defmodule, [line: 1],
         [
           MyModule,
           [do: 1]
         ]}

      assert normalize(ast) ==
               {:defmodule, [line: 1],
                [{:__aliases__, [alias: false], [:MyModule]}, [do: {:__block__, [], [1]}]]}
    end
  end

  test "list" do
    ast = [Aaa, Bbb, Ccc]

    assert normalize(ast) == [
             {:__aliases__, [alias: false], [:Aaa]},
             {:__aliases__, [alias: false], [:Bbb]},
             {:__aliases__, [alias: false], [:Ccc]}
           ]
  end

  describe "try" do
    test "single expression try body" do
      # try do
      #   Aaa
      # after
      #   1
      # end
      ast = {:try, [line: 1], [[do: Aaa, after: 1]]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]},
                    after: {:__block__, [], [1]}
                  ]
                ]}
    end

    test "multiple expressions try body" do
      # try do
      #   :expr_1
      #   :expr_2
      # after
      #   1
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: {:__block__, [], [:expr_1, :expr_2]},
             after: 1
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do:
                      {:__block__, [],
                       [
                         :expr_1,
                         :expr_2
                       ]},
                    after: {:__block__, [], [1]}
                  ]
                ]}
    end

    test "rescue clause with single module (or variable) / single rescue clause / rescue clause with single expression body" do
      # try do
      #   1
      # rescue
      #   Aaa -> Bbb
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             rescue: [
               {:->, [line: 4], [[Aaa], Bbb]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    rescue: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "rescue clause with multiple modules" do
      # try do
      #   1
      # rescue
      #   [Aaa, Bbb] -> Ccc
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             rescue: [
               {:->, [line: 4],
                [
                  [
                    [
                      Aaa,
                      Bbb
                    ]
                  ],
                  Ccc
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    rescue: [
                      {:->, [line: 4],
                       [
                         [
                           [
                             {:__aliases__, [alias: false], [:Aaa]},
                             {:__aliases__, [alias: false], [:Bbb]}
                           ]
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "rescue clause with variable and single module" do
      # try do
      #   1
      # rescue
      #   Aaa in [Bbb] -> Ccc
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             rescue: [
               {:->, [line: 4],
                [
                  [
                    {:in, [line: 4],
                     [
                       Aaa,
                       [Bbb]
                     ]}
                  ],
                  Ccc
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    rescue: [
                      {:->, [line: 4],
                       [
                         [
                           {:in, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              [{:__aliases__, [alias: false], [:Bbb]}]
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "rescue clause with variable and multiple modules" do
      # try do
      #   1
      # rescue
      #   Aaa in [Bbb, Ccc] -> Ddd
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             rescue: [
               {:->, [line: 4],
                [
                  [{:in, [line: 4], [Aaa, [Bbb, Ccc]]}],
                  Ddd
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    rescue: [
                      {:->, [line: 4],
                       [
                         [
                           {:in, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              [
                                {:__aliases__, [alias: false], [:Bbb]},
                                {:__aliases__, [alias: false], [:Ccc]}
                              ]
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "multiple rescue clauses" do
      # try do
      #   1
      # rescue
      #   Aaa in [Bbb, Ccc] -> Ddd
      #   Eee in [Fff, Ggg] -> Hhh
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             rescue: [
               {:->, [line: 4],
                [
                  [{:in, [line: 4], [Aaa, [Bbb, Ccc]]}],
                  Ddd
                ]},
               {:->, [line: 5],
                [
                  [{:in, [line: 5], [Eee, [Fff, Ggg]]}],
                  Hhh
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    rescue: [
                      {:->, [line: 4],
                       [
                         [
                           {:in, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              [
                                {:__aliases__, [alias: false], [:Bbb]},
                                {:__aliases__, [alias: false], [:Ccc]}
                              ]
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                       ]},
                      {:->, [line: 5],
                       [
                         [
                           {:in, [line: 5],
                            [
                              {:__aliases__, [alias: false], [:Eee]},
                              [
                                {:__aliases__, [alias: false], [:Fff]},
                                {:__aliases__, [alias: false], [:Ggg]}
                              ]
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Hhh]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "rescue clause with multiple expressions body" do
      # try do
      #   Aaa
      # rescue
      #   Bbb ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: Aaa,
             rescue: [
               {:->, [line: 4],
                [
                  [Bbb],
                  {:__block__, [],
                   [
                     :expr_1,
                     :expr_2
                   ]}
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]},
                    rescue: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Bbb]}],
                         {:__block__, [],
                          [
                            :expr_1,
                            :expr_2
                          ]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "catch clause with value / single catch clause / catch clause with single expression body" do
      # try do
      #   1
      # catch
      #   Aaa -> Bbb
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4], [[Aaa], Bbb]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "catch clause with value and guard / catch clause with single guard" do
      # try do
      #   1
      # catch
      #   Aaa when Bbb -> Ccc
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4],
                [
                  [
                    {:when, [line: 4],
                     [
                       Aaa,
                       Bbb
                     ]}
                  ],
                  Ccc
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [
                           {:when, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              {:__aliases__, [alias: false], [:Bbb]}
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "catch clause with kind and value" do
      # try do
      #   1
      # catch
      #   Aaa, Bbb -> Ccc
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4],
                [
                  [Aaa, Bbb],
                  Ccc
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [
                           {:__aliases__, [alias: false], [:Aaa]},
                           {:__aliases__, [alias: false], [:Bbb]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "catch clause with kind, value and guard" do
      # try do
      #   1
      # catch
      #   Aaa, Bbb when Ccc -> Ddd
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4],
                [
                  [
                    {:when, [line: 4],
                     [
                       Aaa,
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
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [
                           {:when, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              {:__aliases__, [alias: false], [:Bbb]},
                              {:__aliases__, [alias: false], [:Ccc]}
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "multiple catch clauses" do
      # try do
      #   1
      # catch
      #   Aaa -> Bbb
      #   Ccc -> Ddd
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4], [[Aaa], Bbb]},
               {:->, [line: 5], [[Ccc], Ddd]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]},
                      {:->, [line: 5],
                       [
                         [{:__aliases__, [alias: false], [:Ccc]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "catch clause with multiple expressions body" do
      # try do
      #   1
      # catch
      #   Aaa ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4],
                [
                  [Aaa],
                  {:__block__, [],
                   [
                     :expr_1,
                     :expr_2
                   ]}
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [],
                          [
                            :expr_1,
                            :expr_2
                          ]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "catch clause with multiple guards" do
      # try do
      #   1
      # catch
      #   Aaa when Bbb when Ccc when Ddd -> Eee
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             catch: [
               {:->, [line: 4],
                [
                  [
                    {:when, [line: 4],
                     [
                       Aaa,
                       {:when, [line: 4],
                        [
                          Bbb,
                          {:when, [line: 4],
                           [
                             Ccc,
                             Ddd
                           ]}
                        ]}
                     ]}
                  ],
                  Eee
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    catch: [
                      {:->, [line: 4],
                       [
                         [
                           {:when, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              {:when, [line: 4],
                               [
                                 {:__aliases__, [alias: false], [:Bbb]},
                                 {:when, [line: 4],
                                  [
                                    {:__aliases__, [alias: false], [:Ccc]},
                                    {:__aliases__, [alias: false], [:Ddd]}
                                  ]}
                               ]}
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "single else clause / else clause with single expression body" do
      # try do
      #   1
      # else
      #   Aaa -> Bbb
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             else: [
               {:->, [line: 4], [[Aaa], Bbb]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    else: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "multiple else clauses" do
      # try do
      #   1
      # else
      #   Aaa -> Bbb
      #   Ccc -> Ddd
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             else: [
               {:->, [line: 4], [[Aaa], Bbb]},
               {:->, [line: 5], [[Ccc], Ddd]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    else: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Bbb]}]}
                       ]},
                      {:->, [line: 5],
                       [
                         [{:__aliases__, [alias: false], [:Ccc]}],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ddd]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "else clause with multiple expressions body" do
      # try do
      #   1
      # else
      #   Aaa ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             else: [
               {:->, [line: 4],
                [
                  [Aaa],
                  {:__block__, [],
                   [
                     :expr_1,
                     :expr_2
                   ]}
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    else: [
                      {:->, [line: 4],
                       [
                         [{:__aliases__, [alias: false], [:Aaa]}],
                         {:__block__, [],
                          [
                            :expr_1,
                            :expr_2
                          ]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "else clause with single guard" do
      # try do
      #   1
      # else
      #   Aaa when Bbb -> Ccc
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             else: [
               {:->, [line: 4],
                [
                  [
                    {:when, [line: 4],
                     [
                       Aaa,
                       Bbb
                     ]}
                  ],
                  Ccc
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    else: [
                      {:->, [line: 4],
                       [
                         [
                           {:when, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              {:__aliases__, [alias: false], [:Bbb]}
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Ccc]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "else clause with multiple guards" do
      # try do
      #   1
      # else
      #   Aaa when Bbb when Ccc when Ddd -> Eee
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             else: [
               {:->, [line: 4],
                [
                  [
                    {:when, [line: 4],
                     [
                       Aaa,
                       {:when, [line: 4],
                        [
                          Bbb,
                          {:when, [line: 4],
                           [
                             Ccc,
                             Ddd
                           ]}
                        ]}
                     ]}
                  ],
                  Eee
                ]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    else: [
                      {:->, [line: 4],
                       [
                         [
                           {:when, [line: 4],
                            [
                              {:__aliases__, [alias: false], [:Aaa]},
                              {:when, [line: 4],
                               [
                                 {:__aliases__, [alias: false], [:Bbb]},
                                 {:when, [line: 4],
                                  [
                                    {:__aliases__, [alias: false], [:Ccc]},
                                    {:__aliases__, [alias: false], [:Ddd]}
                                  ]}
                               ]}
                            ]}
                         ],
                         {:__block__, [], [{:__aliases__, [alias: false], [:Eee]}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "single expression after block" do
      # try do
      #   1
      # after
      #   Aaa
      # end
      ast = {:try, [line: 1], [[do: 1, after: Aaa]]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    after: {:__block__, [], [{:__aliases__, [alias: false], [:Aaa]}]}
                  ]
                ]}
    end

    test "multiple expressions after block" do
      # try do
      #   1
      # after
      #   :expr_1
      #   :expr_2
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             after: {:__block__, [], [:expr_1, :expr_2]}
           ]
         ]}

      assert normalize(ast) ==
               {:try, [line: 1],
                [
                  [
                    do: {:__block__, [], [1]},
                    after:
                      {:__block__, [],
                       [
                         :expr_1,
                         :expr_2
                       ]}
                  ]
                ]}
    end
  end

  test "tuple" do
    ast = {Aaa, Bbb, Ccc}

    assert normalize(ast) == {
             {:__aliases__, [alias: false], [:Aaa]},
             {:__aliases__, [alias: false], [:Bbb]},
             {:__aliases__, [alias: false], [:Ccc]}
           }
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

  test "keyword with :do key" do
    # [do: Aaa]
    ast = [do: Aaa]

    assert normalize(ast) == [do: {:__aliases__, [alias: false], [:Aaa]}]
  end

  describe "block" do
    test "with empty meta" do
      # fn Aaa ->
      #   :expr_1
      #   :expr_2
      # end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [Aaa],
              {:__block__, [], [:expr_1, :expr_2]}
            ]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
                  {:->, [line: 1],
                   [
                     [{:__aliases__, [alias: false], [:Aaa]}],
                     {:__block__, [],
                      [
                        :expr_1,
                        :expr_2
                      ]}
                   ]}
                ]}
    end

    test "with non-empty meta" do
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [Aaa],
              {:__block__, [line: 123], [:expr_1, :expr_2]}
            ]}
         ]}

      assert normalize(ast) ==
               {:fn, [line: 1],
                [
                  {:->, [line: 1],
                   [
                     [{:__aliases__, [alias: false], [:Aaa]}],
                     {:__block__, [line: 123],
                      [
                        :expr_1,
                        :expr_2
                      ]}
                   ]}
                ]}
    end

    test "empty block (e.g. empty function body)" do
      # def my_fun do
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}

      assert normalize(ast) ==
               {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}
    end

    test "strips single non-tail alias (import residue)" do
      # def foo do
      #   Kernel <- residue from `import Kernel, only: [...]` inside a function body
      #   bar()
      # end
      ast =
        {:def, [line: 1],
         [
           {:foo, [], []},
           [do: {:__block__, [], [Kernel, {:bar, [line: 3], []}]}]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:foo, [], []},
                  [do: {:__block__, [], [{:bar, [line: 3], []}]}]
                ]}
    end

    test "strips multiple non-tail aliases (multiple import residues)" do
      # def foo do
      #   Kernel
      #   SomeModule
      #   bar()
      # end
      ast =
        {:def, [line: 1],
         [
           {:foo, [], []},
           [do: {:__block__, [], [Kernel, SomeModule, {:bar, [line: 4], []}]}]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:foo, [], []},
                  [do: {:__block__, [], [{:bar, [line: 4], []}]}]
                ]}
    end

    test "preserves tail alias in block" do
      # def foo do
      #   bar()
      #   MyModule
      # end
      ast =
        {:def, [line: 1],
         [
           {:foo, [], []},
           [do: {:__block__, [], [{:bar, [line: 2], []}, MyModule]}]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:foo, [], []},
                  [
                    do:
                      {:__block__, [],
                       [
                         {:bar, [line: 2], []},
                         {:__aliases__, [alias: false], [:MyModule]}
                       ]}
                  ]
                ]}
    end

    test "preserves single-expression block with alias" do
      # def foo, do: MyModule
      ast = {:def, [line: 1], [{:foo, [], []}, [do: MyModule]]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:foo, [], []},
                  [do: {:__block__, [], [{:__aliases__, [alias: false], [:MyModule]}]}]
                ]}
    end

    test "does not strip non-alias atoms from non-tail positions" do
      # def foo do
      #   :ok
      #   bar()
      # end
      ast =
        {:def, [line: 1],
         [
           {:foo, [], []},
           [do: {:__block__, [], [:ok, {:bar, [line: 3], []}]}]
         ]}

      assert normalize(ast) ==
               {:def, [line: 1],
                [
                  {:foo, [], []},
                  [do: {:__block__, [], [:ok, {:bar, [line: 3], []}]}]
                ]}
    end
  end

  describe "special cases" do
    test "variable defmodule" do
      # defmodule
      ast = {:defmodule, [line: 1], nil}

      assert normalize(ast) == ast
    end

    test "variable for" do
      # for
      ast = {:for, [line: 1], nil}

      assert normalize(ast) == ast
    end

    test "variable try" do
      # try
      ast = {:try, [line: 1], nil}

      assert normalize(ast) == ast
    end

    test "variable unquote" do
      # unquote
      ast = {:unquote, [line: 1], nil}

      assert normalize(ast) == ast
    end

    test "def defmodule/0 with block body" do
      ast = fetch_unnormalized_def_ast(Module7)

      assert {:def, meta, [{:defmodule, [], Elixir}, [do: :ok]]} = ast

      assert normalize(ast) ==
               {:def, meta, [{:defmodule, [], Elixir}, [do: {:__block__, [], [:ok]}]]}
    end

    test "def defmodule/0 with expression body" do
      ast = fetch_unnormalized_def_ast(Module8)

      assert {:def, meta, [{:defmodule, [], Elixir}, [do: :ok]]} = ast

      assert normalize(ast) ==
               {:def, meta, [{:defmodule, [], Elixir}, [do: {:__block__, [], [:ok]}]]}
    end

    test "def defmodule/1 with block body" do
      ast = fetch_unnormalized_def_ast(Module9)

      assert {:def, meta_1, [{:defmodule, [], [{:x, meta_2, nil}]}, [do: {:x, meta_3, nil}]]} =
               ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:defmodule, [], [{:x, meta_2, nil}]},
                  [do: {:__block__, [], [{:x, meta_3, nil}]}]
                ]}
    end

    test "def defmodule/1 with expression body" do
      ast = fetch_unnormalized_def_ast(Module10)

      assert {:def, meta_1, [{:defmodule, [], [{:x, meta_2, nil}]}, [do: {:x, meta_3, nil}]]} =
               ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:defmodule, [], [{:x, meta_2, nil}]},
                  [do: {:__block__, [], [{:x, meta_3, nil}]}]
                ]}
    end

    test "def defmodule/2 with block body" do
      ast = fetch_unnormalized_def_ast(Module11)

      assert {:def, meta_1,
              [
                {:defmodule, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                [do: {{:x, meta_4, nil}, {:y, meta_5, nil}}]
              ]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:defmodule, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                  [do: {:__block__, [], [{{:x, meta_4, nil}, {:y, meta_5, nil}}]}]
                ]}
    end

    test "def defmodule/2 with expression body" do
      ast = fetch_unnormalized_def_ast(Module12)

      assert {:def, meta_1,
              [
                {:defmodule, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                [do: {{:x, meta_4, nil}, {:y, meta_5, nil}}]
              ]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:defmodule, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                  [do: {:__block__, [], [{{:x, meta_4, nil}, {:y, meta_5, nil}}]}]
                ]}
    end

    test "def try/0 with block body" do
      ast = fetch_unnormalized_def_ast(Module1)

      assert {:def, meta, [{:try, [], Elixir}, [do: :ok]]} = ast

      assert normalize(ast) == {:def, meta, [{:try, [], Elixir}, [do: {:__block__, [], [:ok]}]]}
    end

    test "def try/0 with expression body" do
      ast = fetch_unnormalized_def_ast(Module2)

      assert {:def, meta, [{:try, [], Elixir}, [do: :ok]]} = ast

      assert normalize(ast) == {:def, meta, [{:try, [], Elixir}, [do: {:__block__, [], [:ok]}]]}
    end

    test "def try/1 with block body" do
      ast = fetch_unnormalized_def_ast(Module3)

      assert {:def, meta_1, [{:try, [], [{:x, meta_2, nil}]}, [do: {:x, meta_3, nil}]]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [{:try, [], [{:x, meta_2, nil}]}, [do: {:__block__, [], [{:x, meta_3, nil}]}]]}
    end

    test "def try/1 with expression body" do
      ast = fetch_unnormalized_def_ast(Module4)

      assert {:def, meta_1, [{:try, [], [{:x, meta_2, nil}]}, [do: {:x, meta_3, nil}]]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [{:try, [], [{:x, meta_2, nil}]}, [do: {:__block__, [], [{:x, meta_3, nil}]}]]}
    end

    test "def try/2 with block body" do
      ast = fetch_unnormalized_def_ast(Module5)

      assert {:def, meta_1,
              [
                {:try, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                [do: {{:x, meta_4, nil}, {:y, meta_5, nil}}]
              ]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:try, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                  [do: {:__block__, [], [{{:x, meta_4, nil}, {:y, meta_5, nil}}]}]
                ]}
    end

    test "def try/2 with expression body" do
      ast = fetch_unnormalized_def_ast(Module6)

      assert {:def, meta_1,
              [
                {:try, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                [do: {{:x, meta_4, nil}, {:y, meta_5, nil}}]
              ]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:try, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                  [do: {:__block__, [], [{{:x, meta_4, nil}, {:y, meta_5, nil}}]}]
                ]}
    end

    test "def unquote/0 with block body" do
      ast = fetch_unnormalized_def_ast(Module13)

      assert {:def, meta, [{:unquote, [], Elixir}, [do: :ok]]} = ast

      assert normalize(ast) ==
               {:def, meta, [{:unquote, [], Elixir}, [do: {:__block__, [], [:ok]}]]}
    end

    test "def unquote/0 with expression body" do
      ast = fetch_unnormalized_def_ast(Module14)

      assert {:def, meta, [{:unquote, [], Elixir}, [do: :ok]]} = ast

      assert normalize(ast) ==
               {:def, meta, [{:unquote, [], Elixir}, [do: {:__block__, [], [:ok]}]]}
    end

    # Won't compile
    # test "def unquote/1 with block body" do

    # Won't compile
    # test "def unquote/1 with expression body" do

    test "def unquote/2 with block body" do
      ast = fetch_unnormalized_def_ast(Module15)

      assert {:def, meta_1,
              [
                {:unquote, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                [do: {{:x, meta_4, nil}, {:y, meta_5, nil}}]
              ]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:unquote, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                  [do: {:__block__, [], [{{:x, meta_4, nil}, {:y, meta_5, nil}}]}]
                ]}
    end

    test "def unquote/2 with expression body" do
      ast = fetch_unnormalized_def_ast(Module16)

      assert {:def, meta_1,
              [
                {:unquote, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                [do: {{:x, meta_4, nil}, {:y, meta_5, nil}}]
              ]} = ast

      assert normalize(ast) ==
               {:def, meta_1,
                [
                  {:unquote, [], [{:x, meta_2, nil}, {:y, meta_3, nil}]},
                  [do: {:__block__, [], [{{:x, meta_4, nil}, {:y, meta_5, nil}}]}]
                ]}
    end
  end

  describe "with" do
    test "does not error when with is used as a variable" do
      # Technically you can use `with` in a way that isn't
      #   the special form syntax, e.g. using `with` as a
      #   variable name. This case should not error, and does not
      #   need any normalization.
      ast = {:with, [line: 1], nil}

      assert normalize(ast) ==
               {:with, [line: 1], nil}
    end

    test "with without any clauses or else clauses, empty body" do
      ast = {:with, [line: 1], [[do: {:__block__, [], []}]]}

      assert normalize(ast) == {:with, [line: 1], [[do: {:__block__, [], []}, else: []]]}
    end

    test "with single clause" do
      ast =
        {:with, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
           [do: {:__block__, [], []}]
         ]}

      assert normalize(ast) ==
               {:with, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
                  [do: {:__block__, [], []}, else: []]
                ]}
    end

    test "with multiple clauses" do
      ast =
        {:with, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
           {:<-, [line: 1], [{:a, [line: 1], nil}, {:b, [line: 1], nil}]},
           [do: {:__block__, [], []}]
         ]}

      assert normalize(ast) ==
               {:with, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
                  {:<-, [line: 1], [{:a, [line: 1], nil}, {:b, [line: 1], nil}]},
                  [do: {:__block__, [], []}, else: []]
                ]}
    end

    test "with else clause" do
      ast =
        {:with, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
           [
             do: {:__block__, [], []},
             else: [
               {:->, [line: 3], [[error: {:msg, [line: 3], nil}], {:msg, [line: 4], nil}]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:with, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
                  [
                    do: {:__block__, [], []},
                    else: [
                      {:->, [line: 3],
                       [
                         [error: {:msg, [line: 3], nil}],
                         {:__block__, [], [{:msg, [line: 4], nil}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "with multiple else clause" do
      ast =
        {:with, [line: 1],
         [
           {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
           [
             do: {:__block__, [], []},
             else: [
               {:->, [line: 3], [[error: {:msg, [line: 3], nil}], {:msg, [line: 4], nil}]},
               {:->, [line: 5], [[ok: {:result, [line: 5], nil}], {:result, [line: 6], nil}]}
             ]
           ]
         ]}

      assert normalize(ast) ==
               {:with, [line: 1],
                [
                  {:<-, [line: 1], [{:x, [line: 1], nil}, {:y, [line: 1], nil}]},
                  [
                    do: {:__block__, [], []},
                    else: [
                      {:->, [line: 3],
                       [
                         [error: {:msg, [line: 3], nil}],
                         {:__block__, [], [{:msg, [line: 4], nil}]}
                       ]},
                      {:->, [line: 5],
                       [
                         [ok: {:result, [line: 5], nil}],
                         {:__block__, [], [{:result, [line: 6], nil}]}
                       ]}
                    ]
                  ]
                ]}
    end

    test "with single expression body" do
      ast = {:with, [line: 1], [[do: :ok]]}

      assert normalize(ast) == {:with, [line: 1], [[do: {:__block__, [], [:ok]}, else: []]]}
    end

    test "with multiple expression body" do
      ast =
        {:with, [line: 1],
         [
           [
             do:
               {:__block__, [],
                [
                  {:=, [line: 2], [{:a, [line: 2], nil}, 1]},
                  {:=, [line: 3], [{:b, [line: 3], nil}, 2]}
                ]}
           ]
         ]}

      assert normalize(ast) ==
               {:with, [line: 1],
                [
                  [
                    do:
                      {:__block__, [],
                       [
                         {:=, [line: 2], [{:a, [line: 2], nil}, 1]},
                         {:=, [line: 3], [{:b, [line: 3], nil}, 2]}
                       ]},
                    else: []
                  ]
                ]}
    end
  end
end
