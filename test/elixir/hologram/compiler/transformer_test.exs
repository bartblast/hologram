defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  describe "anonymous function call" do
    test "without args" do
      ast = ast("test.()")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :test},
               args: []
             }
    end

    test "with args" do
      ast = ast("test.(1, 2)")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :test},
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "anonymous function type" do
    test "single clause, no params, single expression body" do
      ast = ast("fn -> :expr_1 end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 0,
               clauses: [
                 %IR.FunctionClause{
                   params: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 }
               ]
             }
    end

    test "single param" do
      ast = ast("fn x -> :expr_1 end")

      assert %IR.AnonymousFunctionType{
               arity: 1,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple params" do
      ast = ast("fn x, y -> :expr_1 end")

      assert %IR.AnonymousFunctionType{
               arity: 2,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :x},
                     %IR.Variable{name: :y}
                   ]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple expressions body" do
      ast =
        ast("""
        fn x ->
          :expr_1
          :expr_2
        end
        """)

      assert %IR.AnonymousFunctionType{
               clauses: [
                 %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple clauses" do
      ast =
        ast("""
        fn
          x ->
            :expr_1
          y ->
            :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 },
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :y}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_2}]
                   }
                 }
               ]
             }
    end

    test "clause with guard" do
      ast = ast("fn x, y when is_integer(x) -> :expr_1 end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :x},
                     %IR.Variable{name: :y}
                   ],
                   guard: %IR.LocalFunctionCall{
                     function: :is_integer,
                     args: [%IR.Variable{name: :x}]
                   },
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 }
               ]
             }
    end
  end

  describe "atom type" do
    test "boolean" do
      ast = ast("true")

      assert transform(ast, %Context{}) == %IR.AtomType{value: true}
    end

    test "nil" do
      ast = ast("nil")

      assert transform(ast, %Context{}) == %IR.AtomType{value: nil}
    end

    test "other than boolean or nil" do
      ast = ast(":test")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :test}
    end

    test "double quoted" do
      ast = ast(":\"aaa bbb\"")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"aaa bbb"}
    end
  end

  describe "bitstring type" do
    test "empty" do
      ast = ast("<<>>")

      assert transform(ast, %Context{}) == %IR.BitstringType{segments: []}
    end

    test "single segment" do
      ast = ast("<<987>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{}]} = transform(ast, %Context{})
    end

    test "multiple segments" do
      ast = ast("<<987, 876>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{}, %IR.BitstringSegment{}]} =
               transform(ast, %Context{})
    end

    test "nested bitstrings are flattened" do
      ast = ast("<<333, <<444, 555, 666>>, 777>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{value: %IR.IntegerType{value: 333}},
                 %IR.BitstringSegment{value: %IR.IntegerType{value: 444}},
                 %IR.BitstringSegment{value: %IR.IntegerType{value: 555}},
                 %IR.BitstringSegment{value: %IR.IntegerType{value: 666}},
                 %IR.BitstringSegment{value: %IR.IntegerType{value: 777}}
               ]
             } = transform(ast, %Context{})
    end

    # --- ENDIANNESS MODIFIER ---

    test "big endianness modifier" do
      ast = ast("<<xyz::big>>")

      assert %IR.BitstringType{
               segments: [%IR.BitstringSegment{modifiers: [type: :integer, endianness: :big]}]
             } = transform(ast, %Context{})
    end

    test "little endianness modifier" do
      ast = ast("<<xyz::little>>")

      assert %IR.BitstringType{
               segments: [%IR.BitstringSegment{modifiers: [type: :integer, endianness: :little]}]
             } = transform(ast, %Context{})
    end

    test "native endianness modifier" do
      ast = ast("<<xyz::native>>")

      assert %IR.BitstringType{
               segments: [%IR.BitstringSegment{modifiers: [type: :integer, endianness: :native]}]
             } = transform(ast, %Context{})
    end

    # --- SIGNEDNESS MODIFIER ---

    test "signed signedness modifier" do
      ast = ast("<<xyz::signed>>")

      assert %IR.BitstringType{
               segments: [%IR.BitstringSegment{modifiers: [type: :integer, signedness: :signed]}]
             } = transform(ast, %Context{})
    end

    test "unsigned signedness modifier" do
      ast = ast("<<xyz::unsigned>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{modifiers: [type: :integer, signedness: :unsigned]}
               ]
             } = transform(ast, %Context{})
    end

    # --- SIZE MODIFIER ---

    test "explicit size modifier syntax" do
      ast = ast("<<xyz::size(3)>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   modifiers: [type: :integer, size: %IR.IntegerType{value: 3}]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "shorthand size modifier syntax" do
      ast = ast("<<xyz::3>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   modifiers: [type: :integer, size: %IR.IntegerType{value: 3}]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "shorthand size modifier syntax inside size * unit group" do
      ast = ast("<<xyz::3*5>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   modifiers: [type: :integer, unit: 5, size: %IR.IntegerType{value: 3}]
                 }
               ]
             } = transform(ast, %Context{})
    end

    # --- TYPE MODIFIER ---

    test "default type for float literal" do
      ast = ast("<<5.0>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :float]}]} =
               transform(ast, %Context{})
    end

    test "default type for integer literal" do
      ast = ast("<<5>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]} =
               transform(ast, %Context{})
    end

    test "default type for string literal" do
      ast = ast("<<\"abc\">>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :utf8]}]} =
               transform(ast, %Context{})
    end

    test "default type for variable" do
      ast = ast("<<xyz>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]} =
               transform(ast, %Context{})
    end

    test "default type for expression" do
      ast = ast("<<Map.get(my_map, :my_key)>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]} =
               transform(ast, %Context{})
    end

    test "binary type modifier" do
      ast = ast("<<xyz::binary>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :binary]}]} =
               transform(ast, %Context{})
    end

    test "bits type modifier" do
      ast = ast("<<xyz::bits>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :bitstring]}]} =
               transform(ast, %Context{})
    end

    test "bitstring type modifier" do
      ast = ast("<<xyz::bitstring>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :bitstring]}]} =
               transform(ast, %Context{})
    end

    test "bytes type modifier" do
      ast = ast("<<xyz::bytes>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :binary]}]} =
               transform(ast, %Context{})
    end

    test "float type modifier" do
      ast = ast("<<xyz::float>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :float]}]} =
               transform(ast, %Context{})
    end

    test "integer type modifier" do
      ast = ast("<<xyz::integer>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]} =
               transform(ast, %Context{})
    end

    test "utf8 type modifier" do
      ast = ast("<<xyz::utf8>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :utf8]}]} =
               transform(ast, %Context{})
    end

    test "utf16 type modifier" do
      ast = ast("<<xyz::utf16>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :utf16]}]} =
               transform(ast, %Context{})
    end

    test "utf32 type modifier" do
      ast = ast("<<xyz::utf32>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{modifiers: [type: :utf32]}]} =
               transform(ast, %Context{})
    end

    # --- UNIT MODIFIER ---

    test "explicit unit modifier syntax" do
      ast = ast("<<xyz::unit(3)>>")

      assert %IR.BitstringType{
               segments: [%IR.BitstringSegment{modifiers: [type: :integer, unit: 3]}]
             } = transform(ast, %Context{})
    end

    test "shorthand unit modifier syntax inside size * unit group" do
      ast = ast("<<xyz::3*5>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   modifiers: [type: :integer, unit: 5, size: %IR.IntegerType{value: 3}]
                 }
               ]
             } = transform(ast, %Context{})
    end

    # --- VALUE ---

    test "integer value" do
      ast = ast("<<6>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{value: %IR.IntegerType{value: 6}}]} =
               transform(ast, %Context{})
    end

    test "string value" do
      ast = ast("<<\"my_str\">>")

      %IR.BitstringType{segments: [%IR.BitstringSegment{value: %IR.StringType{value: "my_str"}}]} =
        transform(ast, %Context{})
    end

    test "variable value" do
      ast = ast("<<xyz>>")

      assert %IR.BitstringType{segments: [%IR.BitstringSegment{value: %IR.Variable{name: :xyz}}]} =
               transform(ast, %Context{})
    end

    test "expression value" do
      ast = ast("<<Map.get(my_map, :my_key)>>")

      %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.RemoteFunctionCall{
              module: %IR.AtomType{value: Map},
              function: :get,
              args: [%IR.Variable{name: :my_map}, %IR.AtomType{value: :my_key}]
            }
          }
        ]
      } = transform(ast, %Context{})
    end
  end

  test "block" do
    #  1
    #  2
    ast = {:__block__, [], [1, 2]}

    assert transform(ast, %Context{}) == %IR.Block{
             expressions: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  describe "capture operator" do
    test "local function capture" do
      ast = ast("&my_fun/2")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :holo_arg_1__},
                     %IR.Variable{name: :holo_arg_2__}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :holo_arg_1__},
                           %IR.Variable{name: :holo_arg_2__}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote function capture" do
      ast = ast("&Calendar.ISO.parse_date/2")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :holo_arg_1__},
                     %IR.Variable{name: :holo_arg_2__}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Calendar.ISO},
                         function: :parse_date,
                         args: [
                           %IR.Variable{name: :holo_arg_1__},
                           %IR.Variable{name: :holo_arg_2__}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "partially applied local function" do
      ast = ast("&my_fun(&1, 2, [3, &4])")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 4,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :holo_arg_1__},
                     %IR.Variable{name: :holo_arg_2__},
                     %IR.Variable{name: :holo_arg_3__},
                     %IR.Variable{name: :holo_arg_4__}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :holo_arg_1__},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: :holo_arg_4__}
                             ]
                           }
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "partially applied remote function" do
      ast = ast("&Aaa.Bbb.my_fun(&1, 2, [3, &4])")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 4,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :holo_arg_1__},
                     %IR.Variable{name: :holo_arg_2__},
                     %IR.Variable{name: :holo_arg_3__},
                     %IR.Variable{name: :holo_arg_4__}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Aaa.Bbb},
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :holo_arg_1__},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: :holo_arg_4__}
                             ]
                           }
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "partially applied anonymous function" do
      ast = ast("&([&1, 2, my_fun(&3)])")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 3,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :holo_arg_1__},
                     %IR.Variable{name: :holo_arg_2__},
                     %IR.Variable{name: :holo_arg_3__}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.ListType{
                         data: [
                           %IR.Variable{name: :holo_arg_1__},
                           %IR.IntegerType{value: 2},
                           %IR.LocalFunctionCall{
                             function: :my_fun,
                             args: [%IR.Variable{name: :holo_arg_3__}]
                           }
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end
  end

  describe "case" do
    test "single clause without guard, single expression body" do
      ast =
        ast("""
        case x do
          1 -> :expr_1
        end
        """)

      assert transform(ast, %Context{}) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guard: nil,
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 }
               ]
             }
    end

    test "multiple clauses" do
      ast =
        ast("""
        case x do
          1 -> :expr_1
          2 -> :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guard: nil,
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.IntegerType{value: 2},
                   guard: nil,
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_2}]
                   }
                 }
               ]
             }
    end

    test "multiple expressions body" do
      ast =
        ast("""
        case x do
          1 ->
            :expr_1
            :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guard: nil,
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   }
                 }
               ]
             }
    end

    test "guard" do
      ast =
        ast("""
        case x do
          {:ok, n} when is_integer(n) -> :expr_1
        end
        """)

      assert transform(ast, %Context{}) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n}
                     ]
                   },
                   guard: %IR.LocalFunctionCall{
                     function: :is_integer,
                     args: [%IR.Variable{name: :n}]
                   },
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 }
               ]
             }
    end
  end

  describe "comprehension" do
    @ast ast("for a <- [1, 2], do: a * a")

    test "single generator" do
      assert %IR.Comprehension{
               generators: [%IR.Clause{match: %IR.Variable{name: :a}}]
             } = transform(@ast, %Context{})
    end

    test "multiple generators" do
      ast = ast("for a <- [1, 2], b <- [3, 4], do: a * b")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{match: %IR.Variable{name: :a}},
                 %IR.Clause{match: %IR.Variable{name: :b}}
               ]
             } = transform(ast, %Context{})
    end

    test "generator enumerable" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   body: %IR.ListType{
                     data: [
                       %IR.IntegerType{value: 1},
                       %IR.IntegerType{value: 2}
                     ]
                   }
                 }
               ]
             } = transform(@ast, %Context{})
    end

    test "single variable in generator match" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   match: %IR.Variable{name: :a}
                 }
               ]
             } = transform(@ast, %Context{})
    end

    test "multiple variables in generator match" do
      ast = ast("for {a, b} <- [{1, 2}, {3, 4}], do: a * b")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.Variable{name: :a},
                       %IR.Variable{name: :b}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "generator guard" do
      ast = ast("for a when my_guard(a, 2) <- [1, 2, 3], do: a * a")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guard: %IR.LocalFunctionCall{
                     function: :my_guard,
                     args: [
                       %IR.Variable{name: :a},
                       %IR.IntegerType{value: 2}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "no filters" do
      assert %IR.Comprehension{filters: []} = transform(@ast, %Context{})
    end

    test "single filter" do
      ast = ast("for a <- [1, 2], my_filter(a), do: a * a")

      assert %IR.Comprehension{
               filters: [
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter,
                     args: [%IR.Variable{name: :a}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple filters" do
      ast = ast("for a <- [1, 2], my_filter_1(a), my_filter_2(a), do: a * a")

      assert %IR.Comprehension{
               filters: [
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter_1,
                     args: [%IR.Variable{name: :a}]
                   }
                 },
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter_2,
                     args: [%IR.Variable{name: :a}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "default collectable" do
      assert %IR.Comprehension{collectable: %IR.ListType{data: []}} = transform(@ast, %Context{})
    end

    test "custom collectable" do
      ast = ast("for a <- [1, 2], into: my_collectable(123), do: a * a")

      assert %IR.Comprehension{
               collectable: %IR.LocalFunctionCall{
                 function: :my_collectable,
                 args: [%IR.IntegerType{value: 123}]
               }
             } = transform(ast, %Context{})
    end

    test "default unique" do
      assert %IR.Comprehension{unique: %IR.AtomType{value: false}} = transform(@ast, %Context{})
    end

    test "custom unique" do
      ast = ast("for a <- [1, 2], uniq: true, do: a * a")

      assert %IR.Comprehension{unique: %IR.AtomType{value: true}} = transform(ast, %Context{})
    end

    test "mapper" do
      ast = ast("for a <- [1, 2], do: my_mapper(a)")

      assert %IR.Comprehension{
               mapper: %IR.Block{
                 expressions: [
                   %IR.LocalFunctionCall{
                     function: :my_mapper,
                     args: [%IR.Variable{name: :a}]
                   }
                 ]
               },
               reducer: nil
             } = transform(ast, %Context{})
    end

    test "reducer with single clause " do
      ast =
        ast("""
        for x <- [1, 2], reduce: 0 do
          acc -> my_reducer(acc, x)
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guard: nil,
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer,
                           args: [
                             %IR.Variable{name: :acc},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform(ast, %Context{})
    end

    test "reducer with multiple clauses" do
      ast =
        ast("""
        for x <- [1, 2], reduce: 0 do
          1 -> my_reducer_1(acc, x)
          2 -> my_reducer_2(acc, x)
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.IntegerType{value: 1},
                     guard: nil,
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer_1,
                           args: [
                             %IR.Variable{name: :acc},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   },
                   %IR.Clause{
                     match: %IR.IntegerType{value: 2},
                     guard: nil,
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer_2,
                           args: [
                             %IR.Variable{name: :acc},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform(ast, %Context{})
    end

    test "reducer clause with guard" do
      ast =
        ast("""
        for x <- [1, 2], reduce: 0 do
          acc when my_guard(acc) -> my_reducer(acc, x)
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guard: %IR.LocalFunctionCall{
                       function: :my_guard,
                       args: [%IR.Variable{name: :acc}]
                     },
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer,
                           args: [
                             %IR.Variable{name: :acc},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform(ast, %Context{})
    end
  end

  describe "cond" do
    test "single clause, single expression body" do
      ast =
        ast("""
        cond do
          1 -> :expr_1
        end
        """)

      assert transform(ast, %Context{}) == %IR.Cond{
               clauses: [
                 %IR.CondClause{
                   condition: %IR.IntegerType{value: 1},
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 }
               ]
             }
    end

    test "multiple clauses" do
      ast =
        ast("""
        cond do
          1 -> :expr_1
          2 -> :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.Cond{
               clauses: [
                 %IR.CondClause{
                   condition: %IR.IntegerType{value: 1},
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 },
                 %IR.CondClause{
                   condition: %IR.IntegerType{value: 2},
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_2}]
                   }
                 }
               ]
             }
    end

    test "multiple expressions body" do
      ast =
        ast("""
        cond do
          1 ->
            :expr_1
            :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.Cond{
               clauses: [
                 %IR.CondClause{
                   condition: %IR.IntegerType{value: 1},
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   }
                 }
               ]
             }
    end
  end

  test "cons operator" do
    ast = ast("[h | t]")

    assert transform(ast, %Context{}) == %IR.ConsOperator{
             head: %IR.Variable{name: :h},
             tail: %IR.Variable{name: :t}
           }
  end

  test "dot operator" do
    ast = ast("abc.x")

    assert transform(ast, %Context{}) == %IR.DotOperator{
             left: %IR.Variable{name: :abc},
             right: %IR.AtomType{value: :x}
           }
  end

  test "float type" do
    ast = ast("1.0")

    assert transform(ast, %Context{}) == %IR.FloatType{value: 1.0}
  end

  describe "function definition, without guard" do
    test "name" do
      ast =
        ast("""
        def my_fun do
        end
        """)

      assert %IR.FunctionDefinition{name: :my_fun} = transform(ast, %Context{})
    end

    test "no params" do
      ast =
        ast("""
        def my_fun do
        end
        """)

      assert %IR.FunctionDefinition{arity: 0, clause: %IR.FunctionClause{params: []}} =
               transform(ast, %Context{})
    end

    test "single param" do
      ast =
        ast("""
        def my_fun(x) do
        end
        """)

      assert %IR.FunctionDefinition{
               arity: 1,
               clause: %IR.FunctionClause{params: [%IR.Variable{name: :x}]}
             } = transform(ast, %Context{})
    end

    test "multiple params" do
      ast =
        ast("""
        def my_fun(x, y) do
        end
        """)

      assert %IR.FunctionDefinition{
               arity: 2,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}]
               }
             } = transform(ast, %Context{})
    end

    test "empty body" do
      ast =
        ast("""
        def my_fun do
        end
        """)

      assert %IR.FunctionDefinition{clause: %IR.FunctionClause{body: %IR.Block{expressions: []}}} =
               transform(ast, %Context{})
    end

    test "single expression body" do
      ast =
        ast("""
        def my_fun do
          :expr_1
        end
        """)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{expressions: [%IR.AtomType{value: :expr_1}]}
               }
             } = transform(ast, %Context{})
    end

    test "multiple expressions body" do
      ast =
        ast("""
        def my_fun do
          :expr_1
          :expr_2
        end
        """)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
                 }
               }
             } = transform(ast, %Context{})
    end

    test "public visibility" do
      ast =
        ast("""
        def my_fun do
        end
        """)

      assert %IR.FunctionDefinition{visibility: :public} = transform(ast, %Context{})
    end

    test "private visibility" do
      ast =
        ast("""
        defp my_fun do
        end
        """)

      assert %IR.FunctionDefinition{visibility: :private} = transform(ast, %Context{})
    end
  end

  test "function definition, with guard" do
    ast =
      ast("""
      def my_fun(x, y) when :erlang.is_integer(x) do
        1
        2
      end
      """)

    assert %IR.FunctionDefinition{
             name: :my_fun,
             arity: 2,
             visibility: :public,
             clause: %IR.FunctionClause{
               params: [
                 %IR.Variable{name: :x},
                 %IR.Variable{name: :y}
               ],
               guard: %IR.RemoteFunctionCall{
                 module: %IR.AtomType{value: :erlang},
                 function: :is_integer,
                 args: [%IR.Variable{name: :x}]
               },
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               }
             }
           } = transform(ast, %Context{})
  end

  test "integer type" do
    ast = ast("1")

    assert transform(ast, %Context{}) == %IR.IntegerType{value: 1}
  end

  test "list type" do
    ast = ast("[1, 2]")

    assert transform(ast, %Context{}) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  describe "local function call" do
    test "without args" do
      ast = ast("my_fun()")

      assert transform(ast, %Context{}) == %IR.LocalFunctionCall{function: :my_fun, args: []}
    end

    test "with args" do
      ast = ast("my_fun(1, 2)")

      assert transform(ast, %Context{}) == %IR.LocalFunctionCall{
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "macro definition" do
    test "public" do
      ast =
        ast("""
        defmacro my_macro do
          quote do
            :expr
          end
        end
        """)

      assert transform(ast, %Context{}) == %IR.IgnoredExpression{type: :public_macro_definition}
    end

    test "private" do
      ast =
        ast("""
        defmacrop my_macro do
          quote do
            :expr
          end
        end
        """)

      assert transform(ast, %Context{}) == %IR.IgnoredExpression{type: :private_macro_definition}
    end
  end

  describe "map type " do
    test "without cons operator" do
      ast = ast("%{a: 1, b: 2}")

      assert transform(ast, %Context{}) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "with cons operator" do
      ast = ast("%{x | a: 1, b: 2}")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x},
                 %IR.MapType{
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
               ]
             }
    end
  end

  test "match operator" do
    ast = ast("%{a: x, b: y} = %{a: 1, b: 2}")

    assert transform(ast, %Context{}) == %IR.MatchOperator{
             left: %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.Variable{name: :x}},
                 {%IR.AtomType{value: :b}, %IR.Variable{name: :y}}
               ]
             },
             right: %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
           }
  end

  describe "match placeholder" do
    test "with nil value for module" do
      ast = ast("_abc")

      assert transform(ast, %Context{}) == %IR.MatchPlaceholder{}
    end

    test "with non-nil value for module" do
      ast = {:_abc, [line: 1], {:__aliases__, [alias: false], [:Application]}}

      assert transform(ast, %Context{}) == %IR.MatchPlaceholder{}
    end
  end

  describe "module" do
    test "when first alias segment is not 'Elixir'" do
      ast = ast("Aaa.Bbb")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end

    test "when first alias segment is 'Elixir'" do
      ast = ast("Elixir.Aaa.Bbb")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end
  end

  test "module attribute operator" do
    ast = ast("@my_attr")

    assert transform(ast, %Context{}) == %IR.ModuleAttributeOperator{name: :my_attr}
  end

  describe "module definition" do
    test "empty body" do
      ast = ast("defmodule Aaa.Bbb do end")

      assert transform(ast, %Context{}) == %IR.ModuleDefinition{
               module: %IR.AtomType{value: Aaa.Bbb},
               body: %IR.Block{expressions: []}
             }
    end

    test "single expression body" do
      ast =
        ast("""
        defmodule Aaa.Bbb do
          :expr_1
        end
        """)

      assert transform(ast, %Context{}) == %IR.ModuleDefinition{
               module: %IR.AtomType{value: Aaa.Bbb},
               body: %IR.Block{
                 expressions: [%IR.AtomType{value: :expr_1}]
               }
             }
    end

    test "multiple expressions body" do
      ast =
        ast("""
        defmodule Aaa.Bbb do
          :expr_1
          :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.ModuleDefinition{
               module: %IR.AtomType{value: Aaa.Bbb},
               body: %IR.Block{
                 expressions: [
                   %IR.AtomType{value: :expr_1},
                   %IR.AtomType{value: :expr_2}
                 ]
               }
             }
    end
  end

  test "pin operator" do
    ast = ast("^my_var")

    assert transform(ast, %Context{}) == %IR.PinOperator{name: :my_var}
  end

  describe "remote function call" do
    # Remote call on variable, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on variable, without args, with parenthesis" do
      ast = ast("a.x()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :a},
               function: :x,
               args: []
             }
    end

    test "on variable, with args" do
      ast = ast("a.x(1, 2)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :a},
               function: :x,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on alias, without args, without parenthesis" do
      ast = ast("Abc.my_fun")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Abc"},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, without args, with parenthesis" do
      ast = ast("Abc.my_fun()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Abc"},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, with args" do
      ast = ast("Abc.my_fun(1, 2)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Abc"},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # Remote call on module attribute, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on module attribute, without args" do
      ast = ast("@my_attr.my_fun()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: []
             }
    end

    test "on module attribute, with args" do
      ast = ast("@my_attr.my_fun(1, 2)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # Remote call on expression, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on expression, without args" do
      ast = ast("(anon_fun.(1, 2)).remote_fun()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :anon_fun},
                 args: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               },
               function: :remote_fun,
               args: []
             }
    end

    test "on expression, with args" do
      ast = ast("(anon_fun.(1, 2)).remote_fun(3, 4)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :anon_fun},
                 args: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               },
               function: :remote_fun,
               args: [
                 %IR.IntegerType{value: 3},
                 %IR.IntegerType{value: 4}
               ]
             }
    end

    test "on Erlang module, without args, without parenthesis" do
      ast = ast(":my_module.my_fun")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :my_module},
               function: :my_fun,
               args: []
             }
    end

    test "on Erlang module, without args, with parenthesis" do
      ast = ast(":my_module.my_fun()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :my_module},
               function: :my_fun,
               args: []
             }
    end

    test "on Erlang module, with args" do
      ast = ast(":my_module.my_fun(1, 2)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :my_module},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  test "string type" do
    ast = ast("\"abc\"")

    assert transform(ast, %Context{}) == %IR.StringType{value: "abc"}
  end

  describe "struct" do
    @ast ast("%Aaa.Bbb{a: 1, b: 2}")

    test "without cons operator, not in pattern" do
      context = %Context{pattern?: false}

      assert transform(@ast, context) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Aaa.Bbb},
               function: :__struct__,
               args: [
                 %IR.ListType{
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
               ]
             }
    end

    test "without cons operator, in pattern, with module specified" do
      context = %Context{pattern?: true}

      assert transform(@ast, context) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Aaa.Bbb}},
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "without cons operator, in pattern, with variable pattern instead of module" do
      ast = ast("%x{a: 1, b: 2}")

      context = %Context{pattern?: true}

      assert transform(ast, context) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}},
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "without cons operator, in pattern, with match placeholder instead of module" do
      ast = ast("%_{a: 1, b: 2}")

      context = %Context{pattern?: true}

      assert transform(ast, context) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :__struct__}, %IR.MatchPlaceholder{}},
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    # Case not possible, since it wouldn't compile:
    # test "without cons operator, not in pattern, with match placeholder instead of module"

    test "with cons operator, not in pattern" do
      ast = ast("%Aaa.Bbb{x | a: 1, b: 2}")

      context = %Context{pattern?: false}

      assert transform(ast, context) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x},
                 %IR.RemoteFunctionCall{
                   module: %IR.AtomType{value: Aaa.Bbb},
                   function: :__struct__,
                   args: [
                     %IR.ListType{
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
                   ]
                 }
               ]
             }
    end

    # Case not possible, since it wouldn't compile:
    # test "with cons operator, in pattern"
  end

  describe "tuple type" do
    test "2-element tuple" do
      ast = ast("{1, 2}")

      assert transform(ast, %Context{}) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "non-2-element tuple" do
      ast = ast("{1, 2, 3}")

      assert transform(ast, %Context{}) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  describe "variable" do
    test "non-keyword variable name with nil value in AST tuple" do
      ast = ast("my_var")

      assert transform(ast, %Context{}) == %IR.Variable{name: :my_var}
    end

    test "non-keyword variable name with non-nil value in AST tuple" do
      ast = {:my_var, [line: 1], Application}

      assert transform(ast, %Context{}) == %IR.Variable{name: :my_var}
    end

    test "variable 'for' with nil value in AST tuple" do
      ast = ast("for")

      assert transform(ast, %Context{}) == %IR.Variable{name: :for}
    end

    test "variable 'for' with non-nil value in AST tuple" do
      ast = {:for, [line: 1], Application}

      assert transform(ast, %Context{}) == %IR.Variable{name: :for}
    end
  end
end
