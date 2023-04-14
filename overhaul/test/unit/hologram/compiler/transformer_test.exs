defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer

  # --- OPERATORS ---

  describe "pipe operator" do
    test "non-nested pipeline" do
      # 100 |> div(2)
      ast = {:|>, [line: 1], [100, {:div, [line: 1], [2]}]}

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :div,
               args: [
                 %IR.IntegerType{value: 100},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "nested pipeline" do
      # 100 |> div(2) |> div(3)
      ast =
        {:|>, [line: 1],
         [{:|>, [line: 1], [100, {:div, [line: 1], [2]}]}, {:div, [line: 1], [3]}]}

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :div,
               args: [
                 %IR.Call{
                   module: nil,
                   function: :div,
                   args: [
                     %IR.IntegerType{value: 100},
                     %IR.IntegerType{value: 2}
                   ]
                 },
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  test "unary negative operator" do
    # -2
    ast = {:-, [line: 1], [2]}

    assert transform(ast) == %IR.UnaryNegativeOperator{
             value: %IR.IntegerType{value: 2}
           }
  end

  test "unary positive operator" do
    # +2
    ast = {:+, [line: 1], [2]}

    assert transform(ast) == %IR.UnaryPositiveOperator{
             value: %IR.IntegerType{value: 2}
           }
  end

  # --- DIRECTIVES ---

  describe "alias directive" do
    test "default 'as' option" do
      # alias A.B
      ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :B}
    end

    test "custom 'as' option" do
      # alias A.B, as: C
      ast =
        {:alias, [line: 1],
         [{:__aliases__, [line: 1], [:A, :B]}, [as: {:__aliases__, [line: 1], [:C]}]]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
    end

    test "'warn' option" do
      # alias A.B, warn: false
      ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [warn: false]]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :B}
    end

    test "'as' option + 'warn' option" do
      # alias A.B, as: C, warn: false
      ast =
        {:alias, [line: 1],
         [
           {:__aliases__, [line: 1], [:A, :B]},
           [as: {:__aliases__, [line: 1], [:C]}, warn: false]
         ]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
    end

    test "multi-alias without options" do
      # alias A.B.{C, D}
      ast =
        {:alias, [line: 1],
         [
           {{:., [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, :{}]}, [line: 1],
            [{:__aliases__, [line: 1], [:C]}, {:__aliases__, [line: 1], [:D]}]}
         ]}

      assert transform(ast) == [
               %IR.AliasDirective{alias_segs: [:A, :B, :C], as: :C},
               %IR.AliasDirective{alias_segs: [:A, :B, :D], as: :D}
             ]
    end

    test "multi-alias with options" do
      # alias A.B.{C, D}, warn: false
      ast =
        {:alias, [line: 1],
         [
           {{:., [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, :{}]}, [line: 1],
            [{:__aliases__, [line: 1], [:C]}, {:__aliases__, [line: 1], [:D]}]},
           [warn: false]
         ]}

      assert transform(ast) == [
               %IR.AliasDirective{alias_segs: [:A, :B, :C], as: :C},
               %IR.AliasDirective{alias_segs: [:A, :B, :D], as: :D}
             ]
    end
  end

  describe "import directive" do
    test "without options" do
      # import A.B
      ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

      assert transform(ast) == %IR.ImportDirective{alias_segs: [:A, :B], only: [], except: []}
    end

    test "with 'only' option" do
      # import A.B, only: [xyz: 2]
      ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [only: [xyz: 2]]]}

      assert transform(ast) == %IR.ImportDirective{
               alias_segs: [:A, :B],
               only: [xyz: 2],
               except: []
             }
    end

    test "with 'except' option" do
      # import A.B, except: [xyz: 2]
      ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [except: [xyz: 2]]]}

      assert transform(ast) == %IR.ImportDirective{
               alias_segs: [:A, :B],
               only: [],
               except: [xyz: 2]
             }
    end

    test "with both 'only' and 'except' options" do
      # import A.B, only: [abc: 1], except: [xyz: 2]
      ast =
        {:import, [line: 1],
         [{:__aliases__, [line: 1], [:A, :B]}, [only: [abc: 1], except: [xyz: 2]]]}

      assert transform(ast) == %IR.ImportDirective{
               alias_segs: [:A, :B],
               only: [abc: 1],
               except: [xyz: 2]
             }
    end
  end

  test "require directive" do
    # require A.B
    ast = {:require, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

    assert transform(ast) == %IR.IgnoredExpression{type: :require_directive}
  end

  describe "use directive" do
    test "without opts" do
      # use A.B
      ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

      assert transform(ast) == %IR.UseDirective{alias_segs: [:A, :B], opts: []}
    end

    test "with opts" do
      # use A.B, a: 1, b: 2
      ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [a: 1, b: 2]]}

      assert transform(ast) == %IR.UseDirective{
               alias_segs: [:A, :B],
               opts: %IR.ListType{
                 data: [
                   %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :a},
                       %IR.IntegerType{value: 1}
                     ]
                   },
                   %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :b},
                       %IR.IntegerType{value: 2}
                     ]
                   }
                 ]
               }
             }
    end
  end

  # --- CONTROL FLOW ---

  describe "case expression" do
    test "single clause with single expression body" do
      # case x do
      #   1 -> :ok
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [do: [{:->, [line: 2], [[1], {:__block__, [], [:ok]}]}]]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :ok}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 }
               ],
               condition: %IR.Symbol{name: :x}
             }
    end

    test "single clause with multiple expression body" do
      # case x do
      #   1 ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [do: [{:->, [line: 2], [[1], {:__block__, [], [:expr_1, :expr_2]}]}]]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 }
               ],
               condition: %IR.Symbol{name: :x}
             }
    end

    test "multiple clauses with single expression bodies" do
      # case x do
      #   1 -> :ok
      #   2 -> :error
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [
             do: [
               {:->, [line: 2], [[1], {:__block__, [], [:ok]}]},
               {:->, [line: 3], [[2], {:__block__, [], [:error]}]}
             ]
           ]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               condition: %IR.Symbol{name: :x},
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :ok}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 },
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :error}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 2}
                 }
               ]
             }
    end

    test "multiple clauses with multiple expression bodies" do
      # case x do
      #   1 ->
      #     :expr_1
      #     :expr_2
      #   2 ->
      #     :expr_3
      #     :expr_4
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [
             do: [
               {:->, [line: 2], [[1], {:__block__, [], [:expr_1, :expr_2]}]},
               {:->, [line: 5], [[2], {:__block__, [], [:expr_3, :expr_4]}]}
             ]
           ]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               condition: %IR.Symbol{name: :x},
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 },
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_3},
                       %IR.AtomType{value: :expr_4}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 2}
                 }
               ]
             }
    end

    test "clause with bindings" do
      # case x do
      #   %{a: a} -> :ok
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [
             do: [
               {:->, [line: 2],
                [
                  [{:%{}, [line: 2], [a: {:a, [line: 2], nil}]}],
                  {:__block__, [], [:ok]}
                ]}
             ]
           ]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               condition: %IR.Symbol{name: :x},
               clauses: [
                 %{
                   bindings: [
                     %IR.Binding{
                       name: :a,
                       access_path: [
                         %IR.CaseConditionAccess{},
                         %IR.MapAccess{
                           key: %IR.AtomType{value: :a}
                         }
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :ok}
                     ]
                   },
                   pattern: %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :a}, %IR.Symbol{name: :a}}
                     ]
                   }
                 }
               ]
             }
    end
  end

  describe "for expression" do
    test "single generator, single binding" do
      # for n <- [1, 2], do: n * n
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:n, [line: 1], nil}, [1, 2]]},
           [
             do: {:__block__, [], [{:*, [line: 1], [{:n, [line: 1], nil}, {:n, [line: 1], nil}]}]}
           ]
         ]}

      # Enum.reduce([1, 2], [], fn holo_el__, holo_acc__ ->
      #   n = holo_el__
      #   holo_acc__ ++ [n * n]
      # end)
      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Enum]},
               function: :reduce,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.IntegerType{value: 1},
                     %IR.IntegerType{value: 2}
                   ]
                 },
                 %IR.ListType{data: []},
                 %IR.AnonymousFunctionType{
                   arity: 2,
                   params: [
                     %IR.Symbol{name: :holo_el__},
                     %IR.Symbol{name: :holo_acc__}
                   ],
                   bindings: [
                     %IR.Binding{
                       name: :holo_acc__,
                       access_path: [%IR.ParamAccess{index: 1}]
                     },
                     %IR.Binding{
                       name: :holo_el__,
                       access_path: [%IR.ParamAccess{index: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         bindings: [
                           %IR.Binding{
                             name: :n,
                             access_path: [%IR.MatchAccess{}]
                           }
                         ],
                         left: %IR.Symbol{name: :n},
                         right: %IR.Symbol{name: :holo_el__}
                       },
                       %IR.ListConcatenationOperator{
                         left: %IR.Symbol{name: :holo_acc__},
                         right: %IR.ListType{
                           data: [
                             %IR.MultiplicationOperator{
                               left: %IR.Symbol{name: :n},
                               right: %IR.Symbol{name: :n}
                             }
                           ]
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "multiple generators" do
      # for n <- [1, 2], m <- [3, 4], do: n * m
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:n, [line: 1], nil}, [1, 2]]},
           {:<-, [line: 1], [{:m, [line: 1], nil}, [3, 4]]},
           [
             do: {:__block__, [], [{:*, [line: 1], [{:n, [line: 1], nil}, {:m, [line: 1], nil}]}]}
           ]
         ]}

      # Enum.reduce([1, 2], [], fn holo_el__, holo_acc__ ->
      #   n = holo_el__
      #   holo_acc__ ++ Enum.reduce([3, 4], [], fn holo_el__, holo_acc__ ->
      #     m = holo_el__
      #     holo_acc__ ++ [n * m]
      #   end)
      # end)
      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Enum]},
               function: :reduce,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.IntegerType{value: 1},
                     %IR.IntegerType{value: 2}
                   ]
                 },
                 %IR.ListType{data: []},
                 %IR.AnonymousFunctionType{
                   arity: 2,
                   params: [
                     %IR.Symbol{name: :holo_el__},
                     %IR.Symbol{name: :holo_acc__}
                   ],
                   bindings: [
                     %IR.Binding{
                       name: :holo_acc__,
                       access_path: [%IR.ParamAccess{index: 1}]
                     },
                     %IR.Binding{
                       name: :holo_el__,
                       access_path: [%IR.ParamAccess{index: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         bindings: [
                           %IR.Binding{
                             name: :n,
                             access_path: [%IR.MatchAccess{}]
                           }
                         ],
                         left: %IR.Symbol{name: :n},
                         right: %IR.Symbol{name: :holo_el__}
                       },
                       %IR.ListConcatenationOperator{
                         left: %IR.Symbol{name: :holo_acc__},
                         right: %IR.Call{
                           module: %IR.Alias{segments: [:Enum]},
                           function: :reduce,
                           args: [
                             %IR.ListType{
                               data: [
                                 %IR.IntegerType{value: 3},
                                 %IR.IntegerType{value: 4}
                               ]
                             },
                             %IR.ListType{data: []},
                             %IR.AnonymousFunctionType{
                               arity: 2,
                               params: [
                                 %IR.Symbol{name: :holo_el__},
                                 %IR.Symbol{name: :holo_acc__}
                               ],
                               bindings: [
                                 %IR.Binding{
                                   name: :holo_acc__,
                                   access_path: [%IR.ParamAccess{index: 1}]
                                 },
                                 %IR.Binding{
                                   name: :holo_el__,
                                   access_path: [%IR.ParamAccess{index: 0}]
                                 }
                               ],
                               body: %IR.Block{
                                 expressions: [
                                   %IR.MatchOperator{
                                     bindings: [
                                       %IR.Binding{
                                         name: :m,
                                         access_path: [%IR.MatchAccess{}]
                                       }
                                     ],
                                     left: %IR.Symbol{name: :m},
                                     right: %IR.Symbol{name: :holo_el__}
                                   },
                                   %IR.ListConcatenationOperator{
                                     left: %IR.Symbol{name: :holo_acc__},
                                     right: %IR.ListType{
                                       data: [
                                         %IR.MultiplicationOperator{
                                           left: %IR.Symbol{name: :n},
                                           right: %IR.Symbol{name: :m}
                                         }
                                       ]
                                     }
                                   }
                                 ]
                               }
                             }
                           ]
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "single generator, multiple bindings" do
      # for {a, b} <- [{1, 2}, {3, 4}], do: a * b
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{{:a, [line: 1], nil}, {:b, [line: 1], nil}}, [{1, 2}, {3, 4}]]},
           [
             do: {:__block__, [], [{:*, [line: 1], [{:a, [line: 1], nil}, {:b, [line: 1], nil}]}]}
           ]
         ]}

      # Enum.reduce([{1, 2}, {3, 4}], [], fn holo_el__, holo_acc__ ->
      #   {a, b} = holo_el__
      #   holo_acc__ ++ [a * b]
      # end)
      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Enum]},
               function: :reduce,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.TupleType{
                       data: [
                         %IR.IntegerType{value: 1},
                         %IR.IntegerType{value: 2}
                       ]
                     },
                     %IR.TupleType{
                       data: [
                         %IR.IntegerType{value: 3},
                         %IR.IntegerType{value: 4}
                       ]
                     }
                   ]
                 },
                 %IR.ListType{data: []},
                 %IR.AnonymousFunctionType{
                   arity: 2,
                   params: [
                     %IR.Symbol{name: :holo_el__},
                     %IR.Symbol{name: :holo_acc__}
                   ],
                   bindings: [
                     %IR.Binding{
                       name: :holo_acc__,
                       access_path: [%IR.ParamAccess{index: 1}]
                     },
                     %IR.Binding{
                       name: :holo_el__,
                       access_path: [%IR.ParamAccess{index: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         bindings: [
                           %IR.Binding{
                             name: :a,
                             access_path: [
                               %IR.MatchAccess{},
                               %IR.TupleAccess{index: 0}
                             ]
                           },
                           %IR.Binding{
                             name: :b,
                             access_path: [
                               %IR.MatchAccess{},
                               %IR.TupleAccess{index: 1}
                             ]
                           }
                         ],
                         left: %IR.TupleType{
                           data: [
                             %IR.Symbol{name: :a},
                             %IR.Symbol{name: :b}
                           ]
                         },
                         right: %IR.Symbol{name: :holo_el__}
                       },
                       %IR.ListConcatenationOperator{
                         left: %IR.Symbol{name: :holo_acc__},
                         right: %IR.ListType{
                           data: [
                             %IR.MultiplicationOperator{
                               left: %IR.Symbol{name: :a},
                               right: %IR.Symbol{name: :b}
                             }
                           ]
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end
  end

  test "if expression" do
    # if true do
    #   1
    #   2
    # else
    #   3
    #   4
    # end
    ast = {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3, 4]}]]}

    assert transform(ast) == %IR.IfExpression{
             condition: %IR.BooleanType{value: true},
             do: %IR.Block{
               expressions: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             },
             else: %IR.Block{
               expressions: [
                 %IR.IntegerType{value: 3},
                 %IR.IntegerType{value: 4}
               ]
             }
           }
  end
end
