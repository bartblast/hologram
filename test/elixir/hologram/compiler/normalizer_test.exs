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
      #   Bbb
      #   Ccc
      # end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [Aaa],
              {:__block__, [], [Bbb, Ccc]}
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
                        {:__aliases__, [alias: false], [:Bbb]},
                        {:__aliases__, [alias: false], [:Ccc]}
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
      #     Ccc
      #     Ddd
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
                     Ccc,
                     Ddd
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
                            {:__aliases__, [alias: false], [:Ccc]},
                            {:__aliases__, [alias: false], [:Ddd]}
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
      #     Ccc
      #     Ddd
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
                     Ccc,
                     Ddd
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
                                 {:__aliases__, [alias: false], [:Ccc]},
                                 {:__aliases__, [alias: false], [:Ddd]}
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
      #     Bbb
      #     Ccc
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
                     Bbb,
                     Ccc
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
                            {:__aliases__, [alias: false], [:Bbb]},
                            {:__aliases__, [alias: false], [:Ccc]}
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
      #   Bbb
      #   Ccc
      # end
      ast =
        {:def, [line: 1],
         [
           Aaa,
           [
             do: {:__block__, [], [Bbb, Ccc]}
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
                         {:__aliases__, [alias: false], [:Bbb]},
                         {:__aliases__, [alias: false], [:Ccc]}
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
      #   Bbb
      #   Ccc
      # end
      ast =
        {:defp, [line: 1],
         [
           Aaa,
           [
             do: {:__block__, [], [Bbb, Ccc]}
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
                         {:__aliases__, [alias: false], [:Bbb]},
                         {:__aliases__, [alias: false], [:Ccc]}
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
      #   Aaa
      #   Bbb
      # after
      #   1
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: {:__block__, [], [Aaa, Bbb]},
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
                         {:__aliases__, [alias: false], [:Aaa]},
                         {:__aliases__, [alias: false], [:Bbb]}
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
      #     Ccc
      #     Ddd
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
                     Ccc,
                     Ddd
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
                            {:__aliases__, [alias: false], [:Ccc]},
                            {:__aliases__, [alias: false], [:Ddd]}
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
      #     Bbb
      #     Ccc
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
                     Bbb,
                     Ccc
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
                            {:__aliases__, [alias: false], [:Bbb]},
                            {:__aliases__, [alias: false], [:Ccc]}
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
      #     Bbb
      #     Ccc
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
                     Bbb,
                     Ccc
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
                            {:__aliases__, [alias: false], [:Bbb]},
                            {:__aliases__, [alias: false], [:Ccc]}
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
      #   Aaa
      #   Bbb
      # end
      ast =
        {:try, [line: 1],
         [
           [
             do: 1,
             after: {:__block__, [], [Aaa, Bbb]}
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
                         {:__aliases__, [alias: false], [:Aaa]},
                         {:__aliases__, [alias: false], [:Bbb]}
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

  test "for variable" do
    # for
    ast = {:for, [line: 1], nil}

    assert normalize(ast) == ast
  end

  test "try variable" do
    # try
    ast = {:try, [line: 1], nil}

    assert normalize(ast) == ast
  end

  describe "block" do
    test "with empty meta" do
      # fn Aaa ->
      #   Bbb
      #   Ccc
      # end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [Aaa],
              {:__block__, [], [Bbb, Ccc]}
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
                        {:__aliases__, [alias: false], [:Bbb]},
                        {:__aliases__, [alias: false], [:Ccc]}
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
              {:__block__, [line: 123], [Bbb, Ccc]}
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
                        {:__aliases__, [alias: false], [:Bbb]},
                        {:__aliases__, [alias: false], [:Ccc]}
                      ]}
                   ]}
                ]}
    end
  end
end
