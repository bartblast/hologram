# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module10
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module11
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module12
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module13
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module14
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module15
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module16
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module17
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module18
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module19
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module2
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module20
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module21
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module22
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module23
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module24
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module25
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module26
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module27
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module28
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module29
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module3
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module30
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module31
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module32
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module33
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module34
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module35
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module36
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module37
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module38
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module39
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module4
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module40
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module41
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module42
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module43
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module44
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module45
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module46
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module47
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module48
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module49
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module5
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module50
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module51
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module52
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module53
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module54
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module55
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module56
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module57
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module58
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module59
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module6
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module60
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module61
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module62
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module63
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module7
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module8
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module9

  defp fetch_expression(module_ir) do
    module_ir.body.expressions
    |> hd()
    |> Map.get(:clause)
    |> Map.get(:body)
    |> Map.get(:expressions)
    |> hd()
  end

  defp transform_module_and_fetch_expr(module, context \\ %Context{}) do
    module
    |> AST.for_module()
    |> transform(context)
    |> fetch_expression()
  end

  describe "anonymous function call" do
    test "without args (AST from source code)" do
      ast = ast("my_fun.()")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :my_fun},
               args: []
             }
    end

    test "without args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module9) ==
               %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :my_fun},
                 args: []
               }
    end

    test "with args (AST from source code)" do
      ast = ast("my_fun.(1, 2)")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :my_fun},
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "with args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module10) == %IR.AnonymousFunctionCall{
               function: %IR.Variable{name: :my_fun},
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "anonymous function type" do
    test "single clause / single expression body / no params / clause without guards (AST from source code)" do
      ast = ast("fn -> :ok end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 0,
               clauses: [
                 %IR.FunctionClause{
                   params: [],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             }
    end

    test "single clause / single expression body / no params / clause without guards (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module11) == %IR.AnonymousFunctionType{
               arity: 0,
               clauses: [
                 %IR.FunctionClause{
                   params: [],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             }
    end

    test "single param (AST from source code)" do
      ast = ast("fn x -> x end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "single param (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module12) ==
               %IR.AnonymousFunctionType{
                 arity: 1,
                 clauses: [
                   %IR.FunctionClause{
                     params: [%IR.Variable{name: :x}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.Variable{name: :x}]
                     }
                   }
                 ]
               }
    end

    test "multiple params (AST from source code)" do
      ast = ast("fn x, y -> {x, y} end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :x},
                     %IR.Variable{name: :y}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :x}, %IR.Variable{name: :y}]}
                     ]
                   }
                 }
               ]
             }
    end

    test "multiple params (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module13) == %IR.AnonymousFunctionType{
               arity: 2,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :x},
                     %IR.Variable{name: :y}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :x}, %IR.Variable{name: :y}]}
                     ]
                   }
                 }
               ]
             }
    end

    test "multiple expressions body (AST from source code)" do
      ast =
        ast("""
        fn ->
          :expr_1
          :expr_2
        end
        """)

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 0,
               clauses: [
                 %IR.FunctionClause{
                   params: [],
                   guards: [],
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

    test "multiple expressions body (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module14) == %IR.AnonymousFunctionType{
               arity: 0,
               clauses: [
                 %IR.FunctionClause{
                   params: [],
                   guards: [],
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

    test "multiple clauses (AST from source code)" do
      ast =
        ast("""
        fn
          1 -> :ok
          2 -> :error
        end
        """)

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.IntegerType{value: 1}],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 },
                 %IR.FunctionClause{
                   params: [%IR.IntegerType{value: 2}],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :error}]
                   }
                 }
               ]
             }
    end

    test "multiple clauses (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module16) == %IR.AnonymousFunctionType{
               arity: 1,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.IntegerType{value: 1}],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 },
                 %IR.FunctionClause{
                   params: [%IR.IntegerType{value: 2}],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :error}]
                   }
                 }
               ]
             }
    end

    test "clause with single guard (AST from source code)" do
      ast = ast("fn x when is_integer(x) -> x end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "clause with single guard (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module17) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "clause with 2 guards (AST from source code)" do
      ast = ast("fn x when is_integer(x) when x > 1 -> x end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.IntegerType{value: 1}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "clause with 2 guards (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module18) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.IntegerType{value: 1}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "clause with 3 guards (AST from source code)" do
      ast = ast("fn x when is_integer(x) when x > 1 when x < 9 -> x end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.IntegerType{value: 1}
                       ]
                     },
                     %IR.LocalFunctionCall{
                       function: :<,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.IntegerType{value: 9}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "clause with 3 guards (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module19) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :x}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.IntegerType{value: 1}
                       ]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.IntegerType{value: 9}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "params are transformed as patterns in clauses without guards (AST from source code)" do
      ast = ast("fn %x{} -> x end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}
                       ]
                     }
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "params are transformed as patterns in clauses without guards (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module20) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}
                       ]
                     }
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "params are transformed as patterns in clauses with guards (AST from source code)" do
      ast = ast("fn %x{} when x != MyModule -> x end")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}
                       ]
                     }
                   ],
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :!=,
                       args: [
                         %IR.Variable{name: :x},
                         %IR.AtomType{value: MyModule}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end
  end

  test "params are transformed as patterns in clauses with guards (AST from BEAM file)" do
    assert transform_module_and_fetch_expr(Module21) == %IR.AnonymousFunctionType{
             arity: 1,
             captured_function: nil,
             captured_module: nil,
             clauses: [
               %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}
                     ]
                   }
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :"/=",
                     args: [
                       %IR.Variable{name: :x},
                       %IR.AtomType{value: MyModule}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [%IR.Variable{name: :x}]
                 }
               }
             ]
           }
  end

  describe "atom type" do
    test "boolean (AST from source code)" do
      ast = ast("true")

      assert transform(ast, %Context{}) == %IR.AtomType{value: true}
    end

    test "boolean (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module22) == %IR.AtomType{value: true}
    end

    test "nil (AST from source code)" do
      ast = ast("nil")

      assert transform(ast, %Context{}) == %IR.AtomType{value: nil}
    end

    test "nil (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module23) == %IR.AtomType{value: nil}
    end

    test "other than boolean or nil (AST from source code)" do
      ast = ast(":test")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :test}
    end

    test "other than boolean or nil (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module24) == %IR.AtomType{value: :test}
    end

    test "double quoted (AST from source code)" do
      ast = ast(":\"aaa bbb\"")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"aaa bbb"}
    end

    test "double quoted (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module25) == %IR.AtomType{value: :"aaa bbb"}
    end
  end

  # Consider: all sections have aggregate tests using AST loaded from BEAM file.
  describe "bitstring type" do
    # --- SEGMENTS ---

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

    test "aggregate segments test using AST loaded from BEAM file" do
      ast = AST.for_module(Module8)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{segments: []},
                               %IR.BitstringType{segments: [%IR.BitstringSegment{}]},
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{}, %IR.BitstringSegment{}]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{value: %IR.IntegerType{value: 333}},
                                   %IR.BitstringSegment{value: %IR.IntegerType{value: 444}},
                                   %IR.BitstringSegment{value: %IR.IntegerType{value: 555}},
                                   %IR.BitstringSegment{value: %IR.IntegerType{value: 666}},
                                   %IR.BitstringSegment{value: %IR.IntegerType{value: 777}}
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
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

    test "aggregate endianness modifier test using AST loaded from BEAM file" do
      ast = AST.for_module(Module7)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.MatchOperator{},
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [endianness: :big, type: :integer]
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [endianness: :little, type: :integer]
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [endianness: :native, type: :integer]
                                   }
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
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

    test "aggregate signedness modifier test using AST loaded from BEAM file" do
      ast = AST.for_module(Module6)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.MatchOperator{},
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [signedness: :signed, type: :integer]
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [signedness: :unsigned, type: :integer]
                                   }
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
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

    test "aggregate size modifier test using AST loaded from BEAM file" do
      ast = AST.for_module(Module2)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.MatchOperator{},
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [size: %IR.IntegerType{value: 3}, type: :integer]
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [size: %IR.IntegerType{value: 3}, type: :integer]
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [
                                       size: %IR.IntegerType{value: 3},
                                       unit: 5,
                                       type: :integer
                                     ]
                                   }
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
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

    test "aggregate type modifier test using AST loaded from BEAM file" do
      ast = AST.for_module(Module3)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.MatchOperator{},
                           %IR.MatchOperator{},
                           %IR.MatchOperator{},
                           %IR.MatchOperator{},
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :float]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :binary]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :binary]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :bitstring]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :bitstring]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :binary]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :float]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :integer]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :utf8]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :utf16]}]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{modifiers: [type: :utf32]}]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
             } = transform(ast, %Context{})
    end

    # --- UNIT MODIFIER ---

    test "explicit unit modifier syntax" do
      ast = ast("<<xyz::size(3)-unit(5)>>")

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   modifiers: [type: :integer, unit: 5, size: %IR.IntegerType{value: 3}]
                 }
               ]
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

    test "aggregate unit modifier test using AST loaded from BEAM file" do
      ast = AST.for_module(Module4)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.MatchOperator{},
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [
                                       size: %IR.IntegerType{value: 3},
                                       unit: 5,
                                       type: :integer
                                     ]
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     modifiers: [
                                       size: %IR.IntegerType{value: 3},
                                       unit: 5,
                                       type: :integer
                                     ]
                                   }
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
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

    test "empty bitstring segments are filtered out" do
      ast = ast(~s/<<1, "", 2, "">>/)

      assert %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   value: %IR.IntegerType{value: 1}
                 },
                 %IR.BitstringSegment{
                   value: %IR.IntegerType{value: 2}
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "aggregate value test using AST loaded from BEAM file" do
      ast = AST.for_module(Module5)

      assert %IR.ModuleDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{
                     clause: %IR.FunctionClause{
                       body: %IR.Block{
                         expressions: [
                           %IR.MatchOperator{},
                           %IR.MatchOperator{},
                           %IR.ListType{
                             data: [
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{value: %IR.IntegerType{value: 6}}
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{value: %IR.StringType{value: "my_str"}}
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [%IR.BitstringSegment{value: %IR.Variable{name: :xyz}}]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     value: %IR.RemoteFunctionCall{
                                       module: %IR.AtomType{value: Map},
                                       function: :get,
                                       args: [
                                         %IR.Variable{name: :my_map},
                                         %IR.AtomType{value: :my_key}
                                       ]
                                     }
                                   }
                                 ]
                               },
                               %IR.BitstringType{
                                 segments: [
                                   %IR.BitstringSegment{
                                     value: %IR.IntegerType{value: 1}
                                   },
                                   %IR.BitstringSegment{
                                     value: %IR.IntegerType{value: 2}
                                   }
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     }
                   }
                 ]
               }
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
    test "local function capture (AST from source code)" do
      ast = ast("&my_fun/2")

      assert transform(ast, %Context{module: MyModule}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :my_fun,
               captured_module: MyModule,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "local function capture (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module26, %Context{module: Module26}) ==
               %IR.AnonymousFunctionType{
                 arity: 2,
                 captured_function: :my_fun,
                 captured_module: Module26,
                 clauses: [
                   %IR.FunctionClause{
                     params: [
                       %IR.Variable{name: :"$1"},
                       %IR.Variable{name: :"$2"}
                     ],
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_fun,
                           args: [
                             %IR.Variable{name: :"$1"},
                             %IR.Variable{name: :"$2"}
                           ]
                         }
                       ]
                     }
                   }
                 ]
               }
    end

    test "remote Elixir function capture, single-segment module name (AST from source code)" do
      ast = ast("&DateTime.now/2")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :now,
               captured_module: DateTime,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: DateTime},
                         function: :now,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote Elixir function capture, single-segment module name (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module27) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :now,
               captured_module: DateTime,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: DateTime},
                         function: :now,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote Elixir function capture, multi-segment module name (AST from source code)" do
      ast = ast("&Calendar.ISO.parse_date/2")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :parse_date,
               captured_module: Calendar.ISO,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Calendar.ISO},
                         function: :parse_date,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote Elixir function capture, multi-segment module name (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module28) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :parse_date,
               captured_module: Calendar.ISO,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Calendar.ISO},
                         function: :parse_date,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote Erlang function capture (AST from source code)" do
      ast = ast("&:erlang.binary_to_term/2")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :binary_to_term,
               captured_module: :erlang,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :binary_to_term,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote Erlang function capture (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module29) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :binary_to_term,
               captured_module: :erlang,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :binary_to_term,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote function capture, variable module (AST from source code)" do
      ast = ast("&my_module.my_fun/2")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :my_module},
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "remote function capture, variable module (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module30) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :my_module},
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "partially applied local function (AST from source code)" do
      ast = ast("&my_fun(&1, 2, [3, &2])")

      assert transform(ast, %Context{module: MyModule}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: :"$2"}
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

    test "partially applied local function (AST from BEAM file)" do
      {param_1_name, param_2_name} =
        if Version.compare(System.version(), "1.17.0") in [:gt, :eq] do
          {:"$3", :"$4"}
        else
          {:x1, :x2}
        end

      assert transform_module_and_fetch_expr(Module31) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: param_1_name},
                     %IR.Variable{name: param_2_name}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: param_1_name},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: param_2_name}
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

    test "partially applied remote function (AST from source code)" do
      ast = ast("&Hologram.Test.Fixtures.Compiler.Tranformer.Module32.my_fun(&1, 2, [3, &2])")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Module32},
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: :"$2"}
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

    test "partially applied remote function (AST from BEAM file)" do
      {param_1_name, param_2_name} =
        if Version.compare(System.version(), "1.17.0") in [:gt, :eq] do
          {:"$2", :"$3"}
        else
          {:x1, :x2}
        end

      assert transform_module_and_fetch_expr(Module33) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: param_1_name},
                     %IR.Variable{name: param_2_name}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Module32},
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: param_1_name},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: param_2_name}
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

    test "anonymous function capture (AST from source code)" do
      ast = ast("&(&1 * &2 + &1)")

      assert transform(ast, %Context{}) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :+,
                         args: [
                           %IR.LocalFunctionCall{
                             function: :*,
                             args: [
                               %IR.Variable{name: :"$1"},
                               %IR.Variable{name: :"$2"}
                             ]
                           },
                           %IR.Variable{name: :"$1"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "anonymous function capture (AST from BEAM file)" do
      {param_1_name, param_2_name} =
        if Version.compare(System.version(), "1.17.0") in [:gt, :eq] do
          {:"$2", :"$3"}
        else
          {:x1, :x2}
        end

      assert transform_module_and_fetch_expr(Module15) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: param_1_name},
                     %IR.Variable{name: param_2_name}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :+,
                         args: [
                           %IR.RemoteFunctionCall{
                             module: %IR.AtomType{value: :erlang},
                             function: :*,
                             args: [
                               %IR.Variable{name: param_1_name},
                               %IR.Variable{name: param_2_name}
                             ]
                           },
                           %IR.Variable{name: param_1_name}
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
    test "single clause / clause with single expression body (AST from source code)" do
      ast =
        ast("""
        case x do
          1 -> x
        end
        """)

      assert transform(ast, %Context{}) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "single clause / clause with single expression body (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module34) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             }
    end

    test "multiple clauses (AST from source code)" do
      ast =
        ast("""
        case x do
          1 -> x
          2 -> 3
        end
        """)

      assert transform(ast, %Context{}) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.IntegerType{value: 2},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.IntegerType{value: 3}]
                   }
                 }
               ]
             }
    end

    test "multiple clauses (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module35) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.IntegerType{value: 2},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.IntegerType{value: 3}]
                   }
                 }
               ]
             }
    end

    test "multiple expressions body (AST from source code)" do
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
                   guards: [],
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

    test "multiple expressions body (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module36) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
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

    test "clause with single guard (AST from source code)" do
      ast =
        ast("""
        case x do
          {:ok, n} when is_integer(n) -> n
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
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :n}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n}]
                   }
                 }
               ]
             }
    end

    test "clause with single guard (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module37) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n}
                     ]
                   },
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :n}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n}]
                   }
                 }
               ]
             }
    end

    test "clause with 2 guards (AST from source code)" do
      ast =
        ast("""
        case x do
          {:ok, n} when is_integer(n) when n > 1 -> n
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
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :n}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [%IR.Variable{name: :n}, %IR.IntegerType{value: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n}]
                   }
                 }
               ]
             }
    end

    test "clause with 2 guards (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module38) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n}
                     ]
                   },
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :n}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :n}, %IR.IntegerType{value: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n}]
                   }
                 }
               ]
             }
    end

    test "clause with 3 guards (AST from source code)" do
      ast =
        ast("""
        case x do
          {:ok, n} when is_integer(n) when n > 1 when n < 9 -> n
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
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :n}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [%IR.Variable{name: :n}, %IR.IntegerType{value: 1}]
                     },
                     %IR.LocalFunctionCall{
                       function: :<,
                       args: [%IR.Variable{name: :n}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n}]
                   }
                 }
               ]
             }
    end

    test "clause with 3 guards (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module39) == %IR.Case{
               condition: %IR.Variable{name: :x},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n}
                     ]
                   },
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :n}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :n}, %IR.IntegerType{value: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [%IR.Variable{name: :n}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n}]
                   }
                 }
               ]
             }
    end
  end

  describe "comprehension" do
    @ast ast("for x <- [1, 2], do: x * x")
    @result_from_source_code transform(@ast, %Context{})

    # Can't use transform_module_and_fetch_expr(Module40) here
    @result_from_beam_file Module40
                           |> AST.for_module()
                           |> transform(%Context{})
                           |> Map.get(:body)
                           |> Map.get(:expressions)
                           |> hd()
                           |> Map.get(:clause)
                           |> Map.get(:body)
                           |> Map.get(:expressions)
                           |> hd()

    test "single generator (AST from source code)" do
      assert %IR.Comprehension{
               generators: [%IR.Clause{match: %IR.Variable{name: :x}}]
             } = @result_from_source_code
    end

    test "single generator (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [%IR.Clause{match: %IR.Variable{name: :x}}]
             } = @result_from_beam_file
    end

    test "multiple generators (AST from source code)" do
      ast = ast("for x <- [1, 2], y <- [3, 4], do: x * y")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{match: %IR.Variable{name: :x}},
                 %IR.Clause{match: %IR.Variable{name: :y}}
               ]
             } = transform(ast, %Context{})
    end

    test "multiple generators (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{match: %IR.Variable{name: :x}},
                 %IR.Clause{match: %IR.Variable{name: :y}}
               ]
             } = transform_module_and_fetch_expr(Module41)
    end

    test "generator enumerable (AST from source code)" do
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
             } = @result_from_source_code
    end

    test "generator enumerable (AST from BEAM file)" do
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
             } = @result_from_beam_file
    end

    test "single variable in generator match (AST from source code)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   match: %IR.Variable{name: :x}
                 }
               ]
             } = @result_from_source_code
    end

    test "single variable in generator match (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   match: %IR.Variable{name: :x}
                 }
               ]
             } = @result_from_beam_file
    end

    test "multiple variables in generator match (AST from source code)" do
      ast = ast("for {x, y} <- [{1, 2}, {3, 4}], do: x * y")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.Variable{name: :x},
                       %IR.Variable{name: :y}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple variables in generator match (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.Variable{name: :x},
                       %IR.Variable{name: :y}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module42)
    end

    test "generator with single guard (AST from source code)" do
      ast = ast("for x when is_integer(x) <- [1, 2], do: x * x")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "generator with single guard (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ]
                 }
               ]
             } = transform_module_and_fetch_expr(Module43)
    end

    test "generator with 2 guards (AST from source code)" do
      ast = ast("for x when is_integer(x) when x > 1 <- [1, 2], do: x * x")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                     }
                   ]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "generator with 2 guards (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                     }
                   ]
                 }
               ]
             } = transform_module_and_fetch_expr(Module44)
    end

    test "generator with 3 guards (AST from source code)" do
      ast = ast("for x when is_integer(x) when x > 1 when x < 9 <- [1, 2], do: x * x")

      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                     },
                     %IR.LocalFunctionCall{
                       function: :<,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 9}]
                     }
                   ]
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "generator with 3 guards (AST from BEAM file)" do
      assert %IR.Comprehension{
               generators: [
                 %IR.Clause{
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 9}]
                     }
                   ]
                 }
               ]
             } = transform_module_and_fetch_expr(Module45)
    end

    test "no filters (AST from source code)" do
      assert %IR.Comprehension{filters: []} = @result_from_source_code
    end

    test "no filters (AST from BEAM file)" do
      assert %IR.Comprehension{filters: []} = @result_from_beam_file
    end

    test "single filter (AST from source code)" do
      ast = ast("for x <- [1, 2], my_filter(x), do: x * x")

      assert %IR.Comprehension{
               filters: [
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter,
                     args: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "single filter (AST from BEAM file)" do
      assert %IR.Comprehension{
               filters: [
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter,
                     args: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module46)
    end

    test "multiple filters (AST from source code)" do
      ast = ast("for x <- [1, 2], my_filter_1(x), my_filter_2(x), do: x * x")

      assert %IR.Comprehension{
               filters: [
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter_1,
                     args: [%IR.Variable{name: :x}]
                   }
                 },
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter_2,
                     args: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple filters (AST from BEAM file)" do
      assert %IR.Comprehension{
               filters: [
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter_1,
                     args: [%IR.Variable{name: :x}]
                   }
                 },
                 %IR.ComprehensionFilter{
                   expression: %IR.LocalFunctionCall{
                     function: :my_filter_2,
                     args: [%IR.Variable{name: :x}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module47)
    end

    test "default collectable (AST from source code)" do
      assert %IR.Comprehension{collectable: %IR.ListType{data: []}} = @result_from_source_code
    end

    test "default collectable (AST from BEAM file)" do
      assert %IR.Comprehension{collectable: %IR.ListType{data: []}} = @result_from_beam_file
    end

    test "custom collectable (AST from source code)" do
      ast = ast("for x <- [1, 2], into: my_collectable(123), do: x * x")

      assert %IR.Comprehension{
               collectable: %IR.LocalFunctionCall{
                 function: :my_collectable,
                 args: [%IR.IntegerType{value: 123}]
               }
             } = transform(ast, %Context{})
    end

    test "custom collectable (AST from BEAM file)" do
      assert %IR.Comprehension{
               collectable: %IR.LocalFunctionCall{
                 function: :my_collectable,
                 args: [%IR.IntegerType{value: 123}]
               }
             } = transform_module_and_fetch_expr(Module48)
    end

    test "default unique (AST from source code)" do
      assert %IR.Comprehension{unique: %IR.AtomType{value: false}} = @result_from_source_code
    end

    test "default unique (AST from BEAM file)" do
      assert %IR.Comprehension{unique: %IR.AtomType{value: false}} = @result_from_beam_file
    end

    test "custom unique (AST from source code)" do
      ast = ast("for x <- [1, 2], uniq: true, do: x * x")

      assert %IR.Comprehension{unique: %IR.AtomType{value: true}} = transform(ast, %Context{})
    end

    test "custom unique (AST from BEAM file)" do
      assert %IR.Comprehension{unique: %IR.AtomType{value: true}} =
               transform_module_and_fetch_expr(Module49)
    end

    test "mapper with single expression body (AST from source code)" do
      ast = ast("for x <- [1, 2], do: x")

      assert %IR.Comprehension{
               mapper: %IR.Block{expressions: [%IR.Variable{name: :x}]},
               reducer: nil
             } = transform(ast, %Context{})
    end

    test "mapper with single expression body (AST from BEAM file)" do
      assert %IR.Comprehension{
               mapper: %IR.Block{expressions: [%IR.Variable{name: :x}]},
               reducer: nil
             } = transform_module_and_fetch_expr(Module50)
    end

    test "mapper with multiple expressions body (AST from source code)" do
      ast =
        ast("""
        for x <- [1, 2] do
          :expr
          x
        end
        """)

      assert %IR.Comprehension{
               mapper: %IR.Block{
                 expressions: [
                   %IR.AtomType{value: :expr},
                   %IR.Variable{name: :x}
                 ]
               },
               reducer: nil
             } = transform(ast, %Context{})
    end

    test "mapper with multiple expressions body (AST from BEAM file)" do
      assert %IR.Comprehension{
               mapper: %IR.Block{
                 expressions: [
                   %IR.AtomType{value: :expr},
                   %IR.Variable{name: :x}
                 ]
               },
               reducer: nil
             } = transform_module_and_fetch_expr(Module51)
    end

    test "reducer with single clause (AST from source code)" do
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
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform(ast, %Context{})
    end

    test "reducer with single clause (AST from BEAM file)" do
      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform_module_and_fetch_expr(Module52)
    end

    test "reducer with multiple clauses (AST from source code)" do
      ast =
        ast("""
        for x <- [1, 2], reduce: {1, 9} do
          {1, a} -> my_reducer_1(a, x)
          {2, b} -> my_reducer_2(b, x)
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.TupleType{
                       data: [%IR.IntegerType{value: 1}, %IR.Variable{name: :a}]
                     },
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer_1,
                           args: [
                             %IR.Variable{name: :a},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   },
                   %IR.Clause{
                     match: %IR.TupleType{
                       data: [%IR.IntegerType{value: 2}, %IR.Variable{name: :b}]
                     },
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer_2,
                           args: [
                             %IR.Variable{name: :b},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.TupleType{
                   data: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 9}]
                 }
               }
             } = transform(ast, %Context{})
    end

    test "reducer with multiple clauses (AST from BEAM file)" do
      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.TupleType{
                       data: [%IR.IntegerType{value: 1}, %IR.Variable{name: :a}]
                     },
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer_1,
                           args: [
                             %IR.Variable{name: :a},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   },
                   %IR.Clause{
                     match: %IR.TupleType{
                       data: [%IR.IntegerType{value: 2}, %IR.Variable{name: :b}]
                     },
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_reducer_2,
                           args: [
                             %IR.Variable{name: :b},
                             %IR.Variable{name: :x}
                           ]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.TupleType{
                   data: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 9}]
                 }
               }
             } = transform_module_and_fetch_expr(Module53)
    end

    test "reducer clause with single guard (AST from source code)" do
      ast =
        ast("""
        for x <- [1, 2], reduce: 0 do
          acc when is_integer(x) -> acc + x
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guards: [
                       %IR.LocalFunctionCall{
                         function: :is_integer,
                         args: [%IR.Variable{name: :x}]
                       }
                     ],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :+,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform(ast, %Context{})
    end

    test "reducer clause with single guard (AST from BEAM file)" do
      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guards: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :is_integer,
                         args: [%IR.Variable{name: :x}]
                       }
                     ],
                     body: %IR.Block{
                       expressions: [
                         %IR.RemoteFunctionCall{
                           module: %IR.AtomType{value: :erlang},
                           function: :+,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform_module_and_fetch_expr(Module54)
    end

    test "reducer clause with 2 guards (AST from source code)" do
      ast =
        ast("""
        for x <- [1, 2], reduce: 0 do
          acc when is_integer(x) when x > 1 -> acc + x
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guards: [
                       %IR.LocalFunctionCall{
                         function: :is_integer,
                         args: [%IR.Variable{name: :x}]
                       },
                       %IR.LocalFunctionCall{
                         function: :>,
                         args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                       }
                     ],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :+,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform(ast, %Context{})
    end

    test "reducer clause with 2 guards (AST from BEAM file)" do
      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guards: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :is_integer,
                         args: [%IR.Variable{name: :x}]
                       },
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :>,
                         args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                       }
                     ],
                     body: %IR.Block{
                       expressions: [
                         %IR.RemoteFunctionCall{
                           module: %IR.AtomType{value: :erlang},
                           function: :+,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                         }
                       ]
                     }
                   }
                 ],
                 initial_value: %IR.IntegerType{value: 0}
               }
             } = transform_module_and_fetch_expr(Module55)
    end

    test "reducer clause with 3 guards (AST from source code)" do
      ast =
        ast("""
        for x <- [1, 2], reduce: 0 do
          acc when is_integer(x) when x > 1 when x < 9 -> acc + x
        end
        """)

      assert %IR.Comprehension{
               mapper: nil,
               reducer: %{
                 clauses: [
                   %IR.Clause{
                     match: %IR.Variable{name: :acc},
                     guards: [
                       %IR.LocalFunctionCall{
                         function: :is_integer,
                         args: [%IR.Variable{name: :x}]
                       },
                       %IR.LocalFunctionCall{
                         function: :>,
                         args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                       },
                       %IR.LocalFunctionCall{
                         function: :<,
                         args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 9}]
                       }
                     ],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :+,
                           args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
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

  test "reducer clause with 3 guards (AST from BEAM file)" do
    assert %IR.Comprehension{
             mapper: nil,
             reducer: %{
               clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :acc},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [%IR.Variable{name: :x}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: :erlang},
                         function: :+,
                         args: [%IR.Variable{name: :acc}, %IR.Variable{name: :x}]
                       }
                     ]
                   }
                 }
               ],
               initial_value: %IR.IntegerType{value: 0}
             }
           } = transform_module_and_fetch_expr(Module56)
  end

  describe "cond" do
    test "single clause, single expression body (AST from source code)" do
      ast =
        ast("""
        cond do
          1 -> :expr
        end
        """)

      assert transform(ast, %Context{}) == %IR.Cond{
               clauses: [
                 %IR.CondClause{
                   condition: %IR.IntegerType{value: 1},
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr}]
                   }
                 }
               ]
             }
    end

    test "single clause, single expression body (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module57) == %IR.Cond{
               clauses: [
                 %IR.CondClause{
                   condition: %IR.IntegerType{value: 1},
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr}]
                   }
                 }
               ]
             }
    end

    test "multiple clauses (AST from source code)" do
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

    test "multiple clauses (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module58) == %IR.Cond{
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

    test "multiple expressions body (AST from source code)" do
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

    test "multiple expressions body (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module59) == %IR.Cond{
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

  describe "cons operator" do
    test "1 leading item, proper list (AST from source code)" do
      ast = ast("[1 | []]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ListType{data: []}
             }
    end

    test "1 leading item, proper list (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module60) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ListType{data: []}
             }
    end

    test "2 leading items, proper list (AST from source code)" do
      ast = ast("[1, 2 | []]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.ListType{data: []}
               }
             }
    end

    test "2 leading items, proper list (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module61) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.ListType{data: []}
               }
             }
    end

    test "nested, proper (AST from source code)" do
      ast = ast("[1 | [2 | []]]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.ListType{data: []}
               }
             }
    end

    test "nested, proper (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module62) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.ListType{data: []}
               }
             }
    end

    test "1 leading item, improper list (AST from source code)" do
      ast = ast("[1 | 2]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.IntegerType{value: 2}
             }
    end

    test "1 leading item, improper list (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module63) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.IntegerType{value: 2}
             }
    end

    test "2 leading items, improper list" do
      ast = ast("[1, 2 | 3]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.IntegerType{value: 3}
               }
             }
    end

    test "nested, impproper" do
      ast = ast("[1 | [2 | 3]]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.IntegerType{value: 3}
               }
             }
    end
  end

  describe "dot operator" do
    test "third tuple elem is nil" do
      # {{:., [line: 1], [{:abc, [line: 1], nil}, :x]}, [no_parens: true, line: 1], []}
      ast = ast("abc.x")

      assert transform(ast, %Context{}) == %IR.DotOperator{
               left: %IR.Variable{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end

    test "third tuple elem is a module alias" do
      ast = {{:., [line: 1], [{:abc, [line: 1], Aaa.Bbb}, :x]}, [no_parens: true, line: 1], []}

      assert transform(ast, %Context{}) == %IR.DotOperator{
               left: %IR.Variable{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end
  end

  test "float type" do
    ast = ast("1.0")

    assert transform(ast, %Context{}) == %IR.FloatType{value: 1.0}
  end

  describe "function definition" do
    test "name" do
      ast =
        ast("""
        def my_fun do
        end
        """)

      assert %IR.FunctionDefinition{name: :my_fun} = transform(ast, %Context{})
    end

    test "no params, third tuple elem is nil" do
      # {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}
      ast =
        ast("""
        def my_fun do
        end
        """)

      assert %IR.FunctionDefinition{arity: 0, clause: %IR.FunctionClause{params: []}} =
               transform(ast, %Context{})
    end

    test "no params, third tuple elem is an empty list" do
      ast = {:def, [line: 1], [{:my_fun, [line: 1], []}, [do: {:__block__, [], []}]]}

      assert %IR.FunctionDefinition{arity: 0, clause: %IR.FunctionClause{params: []}} =
               transform(ast, %Context{})
    end

    test "no params, third tuple elem is a module alias" do
      ast = {:def, [line: 1], [{:my_fun, [line: 1], Elixir}, [do: {:__block__, [], []}]]}

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

    test "with single guard" do
      ast =
        ast("""
        def my_fun(x) when guard_1(:a) do
          :expr
        end
        """)

      assert transform(ast, %Context{}) == %IR.FunctionDefinition{
               name: :my_fun,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x}
                 ],
                 guards: [
                   %IR.LocalFunctionCall{
                     function: :guard_1,
                     args: [%IR.AtomType{value: :a}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: :expr}
                   ]
                 }
               }
             }
    end

    test "with 2 guards" do
      ast =
        ast("""
        def my_fun(x) when guard_1(:a) when guard_2(:b) do
          :expr
        end
        """)

      assert transform(ast, %Context{}) == %IR.FunctionDefinition{
               name: :my_fun,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x}
                 ],
                 guards: [
                   %IR.LocalFunctionCall{
                     function: :guard_1,
                     args: [%IR.AtomType{value: :a}]
                   },
                   %IR.LocalFunctionCall{
                     function: :guard_2,
                     args: [%IR.AtomType{value: :b}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: :expr}
                   ]
                 }
               }
             }
    end

    test "with 3 guards" do
      ast =
        ast("""
        def my_fun(x) when guard_1(:a) when guard_2(:b) when guard_3(:c) do
          :expr
        end
        """)

      assert transform(ast, %Context{}) == %IR.FunctionDefinition{
               name: :my_fun,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x}
                 ],
                 guards: [
                   %IR.LocalFunctionCall{
                     function: :guard_1,
                     args: [%IR.AtomType{value: :a}]
                   },
                   %IR.LocalFunctionCall{
                     function: :guard_2,
                     args: [%IR.AtomType{value: :b}]
                   },
                   %IR.LocalFunctionCall{
                     function: :guard_3,
                     args: [%IR.AtomType{value: :c}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: :expr}
                   ]
                 }
               }
             }
    end

    test "params are transformed as patterns" do
      ast = ast("def my_fun(%x{}), do: :ok")

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{data: [{%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}]}
                 ]
               }
             } = transform(ast, %Context{})
    end
  end

  test "integer type" do
    ast = ast("1")

    assert transform(ast, %Context{}) == %IR.IntegerType{value: 1}
  end

  describe "list type" do
    test "empty" do
      ast = ast("[]")

      assert transform(ast, %Context{}) == %IR.ListType{data: []}
    end

    test "1 item" do
      ast = ast("[1]")

      assert transform(ast, %Context{}) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1}
               ]
             }
    end

    test "2 items" do
      ast = ast("[1, 2]")

      assert transform(ast, %Context{}) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
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
                     {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                     {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
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

  test "pid" do
    pid = self()

    assert transform(pid, %Context{}) == %IR.PIDType{value: pid}
  end

  test "pin operator" do
    ast = ast("^my_var")

    assert transform(ast, %Context{}) == %IR.PinOperator{name: :my_var}
  end

  test "port" do
    port = port("0.11")

    assert transform(port, %Context{}) == %IR.PortType{value: port}
  end

  test "reference" do
    reference = make_ref()

    assert transform(reference, %Context{}) == %IR.ReferenceType{value: reference}
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

  describe "try" do
    test "body" do
      ast =
        ast("""
        try do
          1
          2
        rescue
          x -> nil
        end
        """)

      assert %IR.Try{
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               }
             } = transform(ast, %Context{})
    end

    test "rescue clause with single module / single rescue clause" do
      ast =
        ast("""
        try do
          1
        rescue
          Aaa -> :b
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: nil,
                   modules: [%IR.AtomType{value: Aaa}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with multiple modules" do
      ast =
        ast("""
        try do
          1
        rescue
          [Aaa, Bbb] -> :c
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: nil,
                   modules: [%IR.AtomType{value: Aaa}, %IR.AtomType{value: Bbb}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with variable" do
      ast =
        ast("""
        try do
          1
        rescue
          x -> :a
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :a}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with variable and single module" do
      ast =
        ast("""
        try do
          1
        rescue
          x in [Aaa] -> :b
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [%IR.AtomType{value: Aaa}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with variable and multiple modules" do
      ast =
        ast("""
        try do
          1
        rescue
          x in [Aaa, Bbb] -> :c
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [%IR.AtomType{value: Aaa}, %IR.AtomType{value: Bbb}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple rescue clauses" do
      ast =
        ast("""
        try do
          1
        rescue
          x -> :a
          y -> :b
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :a}]
                   }
                 },
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :y},
                   modules: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value / single catch clause" do
      ast =
        ast("""
        try do
          1
        catch
          :a -> :b
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: nil,
                   value: %IR.AtomType{value: :a},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value and single guard" do
      ast =
        ast("""
        try do
          1
        catch
          :a when :b -> :c
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: nil,
                   value: %IR.AtomType{value: :a},
                   guards: [%IR.AtomType{value: :b}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value and 2 guards" do
      ast =
        ast("""
        try do
          1
        catch
          :a when :b when :c -> :d
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: nil,
                   value: %IR.AtomType{value: :a},
                   guards: [%IR.AtomType{value: :b}, %IR.AtomType{value: :c}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :d}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value and 3 guards" do
      ast =
        ast("""
        try do
          1
        catch
          :a when :b when :c when :d -> :e
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: nil,
                   value: %IR.AtomType{value: :a},
                   guards: [
                     %IR.AtomType{value: :b},
                     %IR.AtomType{value: :c},
                     %IR.AtomType{value: :d}
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :e}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind and value" do
      ast =
        ast("""
        try do
          1
        catch
          :a, :b -> :c
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :a},
                   value: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind, value and single guard" do
      ast =
        ast("""
        try do
          1
        catch
          :a, :b when :c -> :d
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :a},
                   value: %IR.AtomType{value: :b},
                   guards: [%IR.AtomType{value: :c}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :d}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind, value and 2 guards" do
      ast =
        ast("""
        try do
          1
        catch
          :a, :b when :c when :d -> :e
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :a},
                   value: %IR.AtomType{value: :b},
                   guards: [%IR.AtomType{value: :c}, %IR.AtomType{value: :d}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :e}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind, value and 3 guards" do
      ast =
        ast("""
        try do
          1
        catch
          :a, :b when :c when :d when :e -> :f
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :a},
                   value: %IR.AtomType{value: :b},
                   guards: [
                     %IR.AtomType{value: :c},
                     %IR.AtomType{value: :d},
                     %IR.AtomType{value: :e}
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :f}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple catch clauses" do
      ast =
        ast("""
        try do
          1
        catch
          :a -> :b
          :c -> :d
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: nil,
                   value: %IR.AtomType{value: :a},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 },
                 %IR.TryCatchClause{
                   kind: nil,
                   value: %IR.AtomType{value: :c},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :d}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "single else clause" do
      ast =
        ast("""
        try do
          1
        else
          :a -> :b
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :a},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple else clauses" do
      ast =
        ast("""
        try do
          1
        else
          :a -> :b
          :c -> :d
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :a},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.AtomType{value: :c},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :d}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "else clause with single guard" do
      ast =
        ast("""
        try do
          1
        else
          :a when :b -> :c
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :a},
                   guards: [%IR.AtomType{value: :b}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "else clause with 2 guards" do
      ast =
        ast("""
        try do
          1
        else
          :a when :b when :c -> :d
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :a},
                   guards: [%IR.AtomType{value: :b}, %IR.AtomType{value: :c}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :d}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "else clause with 3 guards" do
      ast =
        ast("""
        try do
          1
        else
          :a when :b when :c when :d -> :e
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :a},
                   guards: [
                     %IR.AtomType{value: :b},
                     %IR.AtomType{value: :c},
                     %IR.AtomType{value: :d}
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :e}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "after block" do
      ast =
        ast("""
        try do
          1
        after
          2
          3
        end
        """)

      assert %IR.Try{
               after_block: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 2},
                   %IR.IntegerType{value: 3}
                 ]
               }
             } = transform(ast, %Context{})
    end
  end

  describe "tuple type" do
    test "empty" do
      ast = ast("{}")

      assert transform(ast, %Context{}) == %IR.TupleType{data: []}
    end

    test "1 item" do
      ast = ast("{1}")

      assert transform(ast, %Context{}) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1}
               ]
             }
    end

    test "2 items" do
      ast = ast("{1, 2}")

      assert transform(ast, %Context{}) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "3 items" do
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

    test "variable 'try' with nil value in AST tuple" do
      ast = ast("try")

      assert transform(ast, %Context{}) == %IR.Variable{name: :try}
    end

    test "variable 'try' with non-nil value in AST tuple" do
      ast = {:try, [line: 1], Application}

      assert transform(ast, %Context{}) == %IR.Variable{name: :try}
    end

    test "variable 'with' with nil value in AST tuple" do
      ast = ast("with")

      assert transform(ast, %Context{}) == %IR.Variable{name: :with}
    end

    test "variable 'with' with non-nil value in AST tuple" do
      ast = {:with, [line: 1], Application}

      assert transform(ast, %Context{}) == %IR.Variable{name: :with}
    end
  end

  # TODO: finish implementing
  test "with" do
    ast =
      ast("""
      with true <- true do
        :ok
      end
      """)

    assert transform(ast, %Context{}) == %Hologram.Compiler.IR.With{}
  end
end
