# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Commons.TestUtils
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module10
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module100
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module101
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module102
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module103
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module104
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module105
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module106
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module107
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module108
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module109
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module11
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module110
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module111
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module112
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module113
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module114
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module115
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module116
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module117
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module118
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module119
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module12
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module120
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module121
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module122
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module123
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module124
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module125
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module126
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module127
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module128
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module129
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module13
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module130
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module131
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module132
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module133
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module134
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module135
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module136
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module137
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module138
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module139
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module14
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module140
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module141
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module142
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module143
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module144
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module145
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module146
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module147
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module148
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module149
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module15
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module150
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module151
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module152
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module153
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module154
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module155
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
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module64
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module65
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module66
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module67
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module68
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module69
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module7
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module70
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module71
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module72
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module73
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module74
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module75
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module76
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module77
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module78
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module79
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module8
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module80
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module81
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module82
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module83
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module84
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module85
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module86
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module87
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module88
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module89
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module9
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module90
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module91
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module92
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module93
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module94
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module95
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module96
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module97
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module98
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module99

  defp fetch_def(module_ir) do
    hd(module_ir.body.expressions)
  end

  defp fetch_expression(module_ir) do
    module_ir.body.expressions
    |> Enum.filter(fn %IR.FunctionDefinition{name: name} -> name == :test end)
    |> hd()
    |> Map.get(:clause)
    |> Map.get(:body)
    |> Map.get(:expressions)
    |> hd()
  end

  defp transform_module(module, context \\ %Context{}) do
    module
    |> AST.for_module()
    |> transform(context)
  end

  defp transform_module_and_fetch_def(module, context \\ %Context{}) do
    module
    |> transform_module(context)
    |> fetch_def()
  end

  defp transform_module_and_fetch_expr(module, context \\ %Context{}) do
    module
    |> transform_module(context)
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
                 function: %IR.Variable{name: :my_fun, version: 0},
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
               function: %IR.Variable{name: :my_fun, version: 0},
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
                     params: [%IR.Variable{name: :x, version: 0}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.Variable{name: :x, version: 0}]
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
                     %IR.Variable{name: :x, version: 0},
                     %IR.Variable{name: :y, version: 1}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{
                         data: [
                           %IR.Variable{name: :x, version: 0},
                           %IR.Variable{name: :y, version: 1}
                         ]
                       }
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
                   params: [%IR.Variable{name: :x, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x, version: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x, version: 0}]
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
                   params: [%IR.Variable{name: :x, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x, version: 0}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [
                         %IR.Variable{name: :x, version: 0},
                         %IR.IntegerType{value: 1}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x, version: 0}]
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
                   params: [%IR.Variable{name: :x, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x, version: 0}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [
                         %IR.Variable{name: :x, version: 0},
                         %IR.IntegerType{value: 1}
                       ]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [
                         %IR.Variable{name: :x, version: 0},
                         %IR.IntegerType{value: 9}
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x, version: 0}]
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
                         {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x, version: 0}}
                       ]
                     }
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x, version: 0}]
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
                       {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x, version: 0}}
                     ]
                   }
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :"/=",
                     args: [
                       %IR.Variable{name: :x, version: 0},
                       %IR.AtomType{value: MyModule}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [%IR.Variable{name: :x, version: 0}]
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

  describe "local function capture" do
    test "arity 0 (AST from source code)" do
      ast = ast("&my_fun/0")

      assert transform(ast, %Context{module: MyModule}) == %IR.AnonymousFunctionType{
               arity: 0,
               captured_function: :my_fun,
               captured_module: MyModule,
               clauses: [
                 %IR.FunctionClause{
                   params: [],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: []
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "arity 0 (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module155, %Context{module: Module155}) ==
               %IR.AnonymousFunctionType{
                 arity: 0,
                 captured_function: :my_fun,
                 captured_module: Module155,
                 clauses: [
                   %IR.FunctionClause{
                     params: [],
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_fun,
                           args: []
                         }
                       ]
                     }
                   }
                 ]
               }
    end

    test "arity 1 (AST from source code)" do
      ast = ast("&my_fun/1")

      assert transform(ast, %Context{module: MyModule}) == %IR.AnonymousFunctionType{
               arity: 1,
               captured_function: :my_fun,
               captured_module: MyModule,
               clauses: [
                 %IR.FunctionClause{
                   params: [%IR.Variable{name: :"$1"}],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: :"$1"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "arity 1 (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module154, %Context{module: Module154}) ==
               %IR.AnonymousFunctionType{
                 arity: 1,
                 captured_function: :my_fun,
                 captured_module: Module154,
                 clauses: [
                   %IR.FunctionClause{
                     params: [
                       %IR.Variable{name: :"$1"}
                     ],
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.LocalFunctionCall{
                           function: :my_fun,
                           args: [
                             %IR.Variable{name: :"$1"}
                           ]
                         }
                       ]
                     }
                   }
                 ]
               }
    end

    test "arity 2 (AST from source code)" do
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

    test "arity 2 (AST from BEAM file)" do
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
  end

  describe "remote Elixir function capture" do
    test "single-segment module name (AST from source code)" do
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

    test "single-segment module name (AST from BEAM file)" do
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

    test "multi-segment module name (AST from source code)" do
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

    test "multi-segment module name (AST from BEAM file)" do
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
  end

  describe "remote Erlang function capture" do
    test "AST from source code" do
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

    test "AST from BEAM file" do
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
  end

  describe "remote function capture with variable module" do
    test "AST from source code" do
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

    test "AST from BEAM file" do
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
                         module: %IR.Variable{name: :my_module, version: 0},
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
  end

  describe "partially applied local function" do
    test "AST from source code" do
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

    test "AST from BEAM file" do
      {param_1_name, param_1_version, param_2_name, param_2_version} =
        if Version.match?(System.version(), ">= 1.17.0") do
          {:"$3", nil, :"$4", nil}
        else
          {:x1, 0, :x2, 1}
        end

      assert transform_module_and_fetch_expr(Module31) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: param_1_name, version: param_1_version},
                     %IR.Variable{name: param_2_name, version: param_2_version}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: param_1_name, version: param_1_version},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: param_2_name, version: param_2_version}
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
  end

  describe "partially applied remote function" do
    test "AST from source code" do
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

    test "AST from BEAM file" do
      {param_1_name, param_1_version, param_2_name, param_2_version} =
        if Version.match?(System.version(), ">= 1.17.0") do
          {:"$2", nil, :"$3", nil}
        else
          {:x1, 0, :x2, 1}
        end

      assert transform_module_and_fetch_expr(Module33) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: param_1_name, version: param_1_version},
                     %IR.Variable{name: param_2_name, version: param_2_version}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Module32},
                         function: :my_fun,
                         args: [
                           %IR.Variable{name: param_1_name, version: param_1_version},
                           %IR.IntegerType{value: 2},
                           %IR.ListType{
                             data: [
                               %IR.IntegerType{value: 3},
                               %IR.Variable{name: param_2_name, version: param_2_version}
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
  end

  describe "anonymous function capture" do
    test "AST from source code" do
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

    test "AST from BEAM file" do
      {param_1_name, param_1_version, param_2_name, param_2_version} =
        if Version.match?(System.version(), ">= 1.17.0") do
          {:"$2", nil, :"$3", nil}
        else
          {:x1, 0, :x2, 1}
        end

      assert transform_module_and_fetch_expr(Module15) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: nil,
               captured_module: nil,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: param_1_name, version: param_1_version},
                     %IR.Variable{name: param_2_name, version: param_2_version}
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
                               %IR.Variable{name: param_1_name, version: param_1_version},
                               %IR.Variable{name: param_2_name, version: param_2_version}
                             ]
                           },
                           %IR.Variable{name: param_1_name, version: param_1_version}
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
               condition: %IR.Variable{name: :x, version: 0},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x, version: 0}]
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
               condition: %IR.Variable{name: :x, version: 0},
               clauses: [
                 %IR.Clause{
                   match: %IR.IntegerType{value: 1},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :x, version: 0}]
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
               condition: %IR.Variable{name: :x, version: 0},
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
               condition: %IR.Variable{name: :x, version: 0},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n, version: 1}
                     ]
                   },
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :n, version: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n, version: 1}]
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
               condition: %IR.Variable{name: :x, version: 0},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n, version: 1}
                     ]
                   },
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :n, version: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :n, version: 1}, %IR.IntegerType{value: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n, version: 1}]
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
               condition: %IR.Variable{name: :x, version: 0},
               clauses: [
                 %IR.Clause{
                   match: %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :ok},
                       %IR.Variable{name: :n, version: 1}
                     ]
                   },
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :n, version: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :n, version: 1}, %IR.IntegerType{value: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [%IR.Variable{name: :n, version: 1}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.Variable{name: :n, version: 1}]
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
    # credo:disable-for-lines:13 Credo.Check.Warning.MapGetUnsafePass
    @result_from_beam_file Module40
                           |> AST.for_module()
                           |> transform(%Context{})
                           |> Map.get(:body)
                           |> Map.get(:expressions)
                           |> Enum.filter(fn %IR.FunctionDefinition{name: name} ->
                             name == :test
                           end)
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
                   condition: %IR.RemoteFunctionCall{
                     args: [%IR.IntegerType{value: 1}],
                     function: :wrap_term,
                     module: %IR.AtomType{value: TestUtils}
                   },
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :expr_1}]
                   }
                 },
                 %IR.CondClause{
                   condition: %IR.RemoteFunctionCall{
                     args: [%IR.IntegerType{value: 2}],
                     function: :wrap_term,
                     module: %IR.AtomType{value: TestUtils}
                   },
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

    test "2 leading items, improper list (AST from source code)" do
      ast = ast("[1, 2 | 3]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.IntegerType{value: 3}
               }
             }
    end

    test "2 leading items, improper list (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module64) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.IntegerType{value: 3}
               }
             }
    end

    test "nested, impproper (AST from source code)" do
      ast = ast("[1 | [2 | 3]]")

      assert transform(ast, %Context{}) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.IntegerType{value: 3}
               }
             }
    end

    test "nested, impproper (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module65) == %IR.ConsOperator{
               head: %IR.IntegerType{value: 1},
               tail: %IR.ConsOperator{
                 head: %IR.IntegerType{value: 2},
                 tail: %IR.IntegerType{value: 3}
               }
             }
    end
  end

  describe "dot operator" do
    test "AST from source code" do
      ast = ast("my_var.my_key")

      assert transform(ast, %Context{}) == %IR.DotOperator{
               left: %IR.Variable{name: :my_var},
               right: %IR.AtomType{value: :my_key}
             }
    end

    test "AST from BEAM file" do
      assert transform_module_and_fetch_expr(Module66) == %IR.DotOperator{
               left: %IR.Variable{name: :my_var, version: 0},
               right: %IR.AtomType{value: :my_key}
             }
    end
  end

  describe "float type" do
    test "AST from source code" do
      ast = ast("1.0")

      assert transform(ast, %Context{}) == %IR.FloatType{value: 1.0}
    end

    test "AST from BEAM file" do
      assert transform_module_and_fetch_expr(Module67) == %IR.FloatType{value: 1.0}
    end
  end

  describe "function definition" do
    # {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}
    @ast ast("""
         def my_fun do
         end
         """)

    @result_from_source_code transform(@ast, %Context{})

    # Can't use transform_module_and_fetch_def(Module68) here
    # {:def, [line: 3, column: 7], [{:my_fun, [], Elixir}, [do: {:__block__, [], [nil]}]]}
    @result_from_beam_file Module68
                           |> AST.for_module()
                           |> transform(%Context{})
                           |> Map.get(:body)
                           |> Map.get(:expressions)
                           |> hd()

    test "name (AST from source code)" do
      assert %IR.FunctionDefinition{name: :my_fun} = @result_from_source_code
    end

    test "name (AST from BEAM file)" do
      assert %IR.FunctionDefinition{name: :my_fun} = @result_from_beam_file
    end

    test "no params (AST from source code)" do
      assert %IR.FunctionDefinition{arity: 0, clause: %IR.FunctionClause{params: []}} =
               @result_from_source_code
    end

    test "no params (AST from BEAM file)" do
      assert %IR.FunctionDefinition{arity: 0, clause: %IR.FunctionClause{params: []}} =
               @result_from_beam_file
    end

    test "single param (AST from source code)" do
      ast =
        ast("""
        def my_fun(x) do
          x
        end
        """)

      assert %IR.FunctionDefinition{
               arity: 1,
               clause: %IR.FunctionClause{params: [%IR.Variable{name: :x}]}
             } = transform(ast, %Context{})
    end

    test "single param (AST from BEAM file)" do
      assert %IR.FunctionDefinition{
               arity: 1,
               clause: %IR.FunctionClause{params: [%IR.Variable{name: :x}]}
             } = transform_module_and_fetch_def(Module69)
    end

    test "multiple params (AST from source code)" do
      ast =
        ast("""
        def my_fun(x, y) do
          x + y
        end
        """)

      assert %IR.FunctionDefinition{
               arity: 2,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}]
               }
             } = transform(ast, %Context{})
    end

    test "multiple params (AST from BEAM file)" do
      assert %IR.FunctionDefinition{
               arity: 2,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}]
               }
             } = transform_module_and_fetch_def(Module70)
    end

    test "empty body (AST from source code)" do
      assert %IR.FunctionDefinition{clause: %IR.FunctionClause{body: %IR.Block{expressions: []}}} =
               @result_from_source_code
    end

    test "empty body (AST from BEAM file)" do
      # Compiler injects nil expression by default if the body is empty.
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{expressions: [%IR.AtomType{value: nil}]}
               }
             } = @result_from_beam_file
    end

    test "single expression body (AST from source code)" do
      ast =
        ast("""
        def my_fun do
          :ok
        end
        """)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{expressions: [%IR.AtomType{value: :ok}]}
               }
             } = transform(ast, %Context{})
    end

    test "single expression body (AST from BEAM file)" do
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{expressions: [%IR.AtomType{value: :ok}]}
               }
             } = transform_module_and_fetch_def(Module71)
    end

    test "multiple expressions body (AST from source code)" do
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

    test "multiple expressions body (AST from BEAM file)" do
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
                 }
               }
             } = transform_module_and_fetch_def(Module72)
    end

    test "public visibility (AST from source code)" do
      assert %IR.FunctionDefinition{visibility: :public} = @result_from_source_code
    end

    test "public visibility (AST from BEAM file)" do
      assert %IR.FunctionDefinition{visibility: :public} = @result_from_beam_file
    end

    test "private visibility (AST from source code)" do
      ast =
        ast("""
        defp my_fun do
        end
        """)

      assert %IR.FunctionDefinition{visibility: :private} = transform(ast, %Context{})
    end

    test "private visibility (AST from BEAM file)" do
      fun_defs =
        Module73
        |> transform_module()
        |> Map.get(:body)
        |> Map.get(:expressions)

      assert [
               %IR.FunctionDefinition{name: :my_fun_1, visibility: :public},
               %IR.FunctionDefinition{name: :my_fun_2, visibility: :private}
             ] = fun_defs
    end

    test "with single guard (AST from source code)" do
      ast =
        ast("""
        def my_fun(x) when is_integer(x) do
          x
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
                     function: :is_integer,
                     args: [%IR.Variable{name: :x}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Variable{name: :x}
                   ]
                 }
               }
             }
    end

    test "with single guard (AST from BEAM file)" do
      assert transform_module_and_fetch_def(Module74) == %IR.FunctionDefinition{
               name: :my_fun,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x, version: 0}
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_integer,
                     args: [%IR.Variable{name: :x, version: 0}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Variable{name: :x, version: 0}
                   ]
                 }
               }
             }
    end

    test "with 2 guards (AST from source code)" do
      ast =
        ast("""
        def my_fun(x) when is_integer(x) when x > 1 do
          x
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
                     %IR.Variable{name: :x}
                   ]
                 }
               }
             }
    end

    test "with 2 guards (AST from BEAM file)" do
      assert transform_module_and_fetch_def(Module75) == %IR.FunctionDefinition{
               name: :my_fun,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x, version: 0}
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_integer,
                     args: [%IR.Variable{name: :x, version: 0}]
                   },
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :>,
                     args: [%IR.Variable{name: :x, version: 0}, %IR.IntegerType{value: 1}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Variable{name: :x, version: 0}
                   ]
                 }
               }
             }
    end

    test "with 3 guards (AST from source code)" do
      ast =
        ast("""
        def my_fun(x) when is_integer(x) when x > 1 when x < 9 do
          x
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
                     %IR.Variable{name: :x}
                   ]
                 }
               }
             }
    end

    test "with 3 guards (AST from BEAM file)" do
      assert transform_module_and_fetch_def(Module76) == %IR.FunctionDefinition{
               name: :my_fun,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x, version: 0}
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_integer,
                     args: [%IR.Variable{name: :x, version: 0}]
                   },
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :>,
                     args: [%IR.Variable{name: :x, version: 0}, %IR.IntegerType{value: 1}]
                   },
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :<,
                     args: [%IR.Variable{name: :x, version: 0}, %IR.IntegerType{value: 9}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Variable{name: :x, version: 0}
                   ]
                 }
               }
             }
    end

    test "params are transformed as patterns (AST from source code)" do
      ast = ast("def my_fun(%x{}), do: x")

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{data: [{%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}]}
                 ]
               }
             } = transform(ast, %Context{})
    end

    test "params are transformed as patterns (AST from BEAM file)" do
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{data: [{%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}}]}
                 ]
               }
             } = transform_module_and_fetch_def(Module77)
    end
  end

  describe "integer type" do
    test "AST from source code" do
      ast = ast("1")

      assert transform(ast, %Context{}) == %IR.IntegerType{value: 1}
    end

    test "AST from BEAM file" do
      assert transform_module_and_fetch_expr(Module78) == %IR.IntegerType{value: 1}
    end
  end

  describe "list type" do
    test "empty (AST from source code)" do
      ast = ast("[]")

      assert transform(ast, %Context{}) == %IR.ListType{data: []}
    end

    test "empty (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module79) == %IR.ListType{data: []}
    end

    test "1 item (AST from source code)" do
      ast = ast("[1]")

      assert transform(ast, %Context{}) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1}
               ]
             }
    end

    test "1 item (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module80) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1}
               ]
             }
    end

    test "2 items (AST from source code)" do
      ast = ast("[1, 2]")

      assert transform(ast, %Context{}) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "2 items (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module81) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "local function call" do
    test "without args (AST from source code)" do
      ast = ast("my_fun()")

      assert transform(ast, %Context{}) == %IR.LocalFunctionCall{function: :my_fun, args: []}
    end

    test "without args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module82) == %IR.LocalFunctionCall{
               function: :my_fun,
               args: []
             }
    end

    test "with args (AST from source code)" do
      ast = ast("my_fun(1, 2)")

      assert transform(ast, %Context{}) == %IR.LocalFunctionCall{
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "with args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module83) == %IR.LocalFunctionCall{
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  # BEAM files contain expanded AST, so only "AST from source code" tests make sense here.
  describe "macro definition (AST from source code)" do
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

  describe "map type" do
    test "without cons operator (AST from source code)" do
      ast = ast("%{a: 1, b: 2}")

      assert transform(ast, %Context{}) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "without cons operator (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module84) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "with cons operator (AST from source code)" do
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

    test "with cons operator (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module85) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x, version: 0},
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

  describe "match operator" do
    test "AST from source code" do
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

    test "AST from BEAM file" do
      assert transform_module_and_fetch_expr(Module86) == %IR.MatchOperator{
               left: %IR.MapType{
                 data: [
                   {%IR.AtomType{value: :a}, %IR.Variable{name: :x, version: 0}},
                   {%IR.AtomType{value: :b}, %IR.Variable{name: :y, version: 1}}
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
  end

  describe "match placeholder" do
    test "AST from source code" do
      ast = ast("_abc")

      assert transform(ast, %Context{}) == %IR.MatchPlaceholder{}
    end

    test "AST from BEAM file" do
      %IR.MatchOperator{
        left: %IR.MatchPlaceholder{},
        right: _right
      } = transform_module_and_fetch_expr(Module87)
    end
  end

  describe "module" do
    test "when the first alias segment is not 'Elixir' (AST from source code)" do
      ast = ast("Aaa.Bbb")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end

    test "when the first alias segment is not 'Elixir' (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module88) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end

    test "when the first alias segment is 'Elixir' (AST from source code)" do
      ast = ast("Elixir.Aaa.Bbb")

      assert transform(ast, %Context{}) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end

    test "when the first alias segment is 'Elixir' (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module89) == %IR.AtomType{value: :"Elixir.Aaa.Bbb"}
    end
  end

  # BEAM files contain expanded AST, so only "AST from source code" test makes sense here.
  test "module attribute operator (AST from source code)" do
    ast = ast("@my_attr")

    assert transform(ast, %Context{}) == %IR.ModuleAttributeOperator{name: :my_attr}
  end

  describe "module definition" do
    test "empty body (AST from source code)" do
      ast =
        ast("""
        defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module90 do
        end
        """)

      assert transform(ast, %Context{}) == %IR.ModuleDefinition{
               module: %IR.AtomType{value: Module90},
               body: %IR.Block{expressions: []}
             }
    end

    test "empty body (AST from BEAM file)" do
      assert transform_module(Module90) == %IR.ModuleDefinition{
               module: %IR.AtomType{value: Module90},
               body: %IR.Block{expressions: []}
             }
    end

    test "single expression body (AST from source code)" do
      ast =
        ast("""
        defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module91 do
          def my_fun, do: :ok
        end
        """)

      assert %IR.ModuleDefinition{
               module: %IR.AtomType{value: Module91},
               body: %IR.Block{
                 expressions: [%IR.FunctionDefinition{name: :my_fun}]
               }
             } = transform(ast, %Context{})
    end

    test "single expression body (AST from BEAM file)" do
      assert %IR.ModuleDefinition{
               module: %IR.AtomType{value: Module91},
               body: %IR.Block{
                 expressions: [%IR.FunctionDefinition{name: :my_fun}]
               }
             } = transform_module(Module91)
    end

    test "multiple expressions body (AST from source code)" do
      ast =
        ast("""
        defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module92 do
          def my_fun_1, do: :ok
          
          def my_fun_2, do: :ok
        end
        """)

      assert %IR.ModuleDefinition{
               module: %IR.AtomType{value: Module92},
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{name: :my_fun_1},
                   %IR.FunctionDefinition{name: :my_fun_2}
                 ]
               }
             } = transform(ast, %Context{})
    end

    test "multiple expressions body (AST from BEAM file)" do
      assert %IR.ModuleDefinition{
               module: %IR.AtomType{value: Module92},
               body: %IR.Block{
                 expressions: [
                   %IR.FunctionDefinition{name: :my_fun_1},
                   %IR.FunctionDefinition{name: :my_fun_2}
                 ]
               }
             } = transform_module(Module92)
    end
  end

  # Can't compile PID inside quoted expression, so only "AST from source code" test makes sense here.
  test "pid type (AST from source code)" do
    ast = pid = self()

    assert transform(ast, %Context{}) == %IR.PIDType{value: pid}
  end

  describe "pin operator" do
    test "AST from source code" do
      ast = ast("^my_var")

      assert transform(ast, %Context{}) == %IR.PinOperator{
               variable: %IR.Variable{name: :my_var, version: nil}
             }
    end

    test "AST from BEAM file" do
      %IR.MatchOperator{
        left: %IR.PinOperator{variable: %IR.Variable{name: :my_var, version: 0}},
        right: _right
      } = transform_module_and_fetch_expr(Module93)
    end
  end

  # Can't inject a module attribute with port value into a function,
  # so only "AST from source code" test makes sense here.
  test "port (AST from source code)" do
    ast = port = port("0.11")

    assert transform(ast, %Context{}) == %IR.PortType{value: port}
  end

  # Can't inject a module attribute with reference value into a function,
  # so only "AST from source code" test makes sense here.
  test "reference (AST from source code)" do
    ast = reference = make_ref()

    assert transform(ast, %Context{}) == %IR.ReferenceType{value: reference}
  end

  describe "remote function call" do
    # Remote call on variable, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    test "on variable, without args, with parenthesis (AST from source code)" do
      ast = ast("x.my_fun()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :x},
               function: :my_fun,
               args: []
             }
    end

    test "on variable, without args, with parenthesis (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module94) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :x, version: 0},
               function: :my_fun,
               args: []
             }
    end

    test "on variable, with args (AST from source code)" do
      ast = ast("x.my_fun(1, 2)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :x},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on variable, with args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module95) == %IR.RemoteFunctionCall{
               module: %IR.Variable{name: :x, version: 0},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on alias, without args, without parenthesis (AST from source code)" do
      ast = ast("DateTime.utc_now")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.DateTime"},
               function: :utc_now,
               args: []
             }
    end

    test "on alias, without args, without parenthesis (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module96) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.DateTime"},
               function: :utc_now,
               args: []
             }
    end

    test "on alias, without args, with parenthesis (AST from source code)" do
      ast = ast("DateTime.utc_now()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.DateTime"},
               function: :utc_now,
               args: []
             }
    end

    test "on alias, without args, with parenthesis (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module97) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.DateTime"},
               function: :utc_now,
               args: []
             }
    end

    test "on alias, with args (AST from source code)" do
      ast = ast("Integer.digits(123, 10)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Integer"},
               function: :digits,
               args: [
                 %IR.IntegerType{value: 123},
                 %IR.IntegerType{value: 10}
               ]
             }
    end

    test "on alias, with args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module98) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :"Elixir.Integer"},
               function: :digits,
               args: [
                 %IR.IntegerType{value: 123},
                 %IR.IntegerType{value: 10}
               ]
             }
    end

    # Remote call on module attribute, without args, without parenthesis case
    # is tested as part of the dot operator tests.

    # BEAM files contain expanded AST, so only "AST from source code" tests make sense here.
    test "on module attribute, without args (AST from source code)" do
      ast = ast("@my_attr.my_fun()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: []
             }
    end

    # BEAM files contain expanded AST, so only "AST from source code" tests make sense here.
    test "on module attribute, with args (AST from source code)" do
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

    test "on expression, without args (AST from source code)" do
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

    test "on expression, without args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module99) == %IR.RemoteFunctionCall{
               module: %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :anon_fun, version: 0},
                 args: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               },
               function: :remote_fun,
               args: []
             }
    end

    test "on expression, with args (AST from source code)" do
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

    test "on expression, with args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module100) == %IR.RemoteFunctionCall{
               module: %IR.AnonymousFunctionCall{
                 function: %IR.Variable{name: :anon_fun, version: 0},
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

    test "on Erlang module, without args, without parenthesis (AST from source code)" do
      ast = ast(":maps.new")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :maps},
               function: :new,
               args: []
             }
    end

    test "on Erlang module, without args, without parenthesis (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module101) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :maps},
               function: :new,
               args: []
             }
    end

    test "on Erlang module, without args, with parenthesis (AST from source code)" do
      ast = ast(":maps.new()")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :maps},
               function: :new,
               args: []
             }
    end

    test "on Erlang module, without args, with parenthesis (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module102) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :maps},
               function: :new,
               args: []
             }
    end

    test "on Erlang module, with args (AST from source code)" do
      ast = ast(":math.pow(2, 3)")

      assert transform(ast, %Context{}) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :math},
               function: :pow,
               args: [
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end

    test "on Erlang module, with args (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module103) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :math},
               function: :pow,
               args: [
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  describe "string type" do
    test "AST from source code" do
      ast = ast("\"abc\"")

      assert transform(ast, %Context{}) == %IR.StringType{value: "abc"}
    end

    test "AST from BEAM file" do
      assert transform_module_and_fetch_expr(Module104) == %IR.StringType{value: "abc"}
    end
  end

  describe "struct" do
    @ast ast("%Hologram.Test.Fixtures.Compiler.Tranformer.Module105{a: 1, b: 2}")

    test "without cons operator, not in pattern (AST from source code)" do
      context = %Context{pattern?: false}

      assert transform(@ast, context) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Module105},
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

    test "without cons operator, not in pattern (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module105) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Module105},
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

    test "without cons operator, in pattern, with module specified (AST from source code)" do
      context = %Context{pattern?: true}

      assert transform(@ast, context) == %IR.MapType{
               data: [
                 {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module105}},
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "without cons operator, in pattern, with module specified (AST from BEAM file)" do
      assert %IR.MatchOperator{
               left: %IR.MapType{
                 data: [
                   {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module106}},
                   {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                   {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
                 ]
               },
               right: _right
             } = transform_module_and_fetch_expr(Module106)
    end

    test "without cons operator, in pattern, with variable pattern instead of module (AST from source code)" do
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

    test "without cons operator, in pattern, with variable pattern instead of module (AST from BEAM file)" do
      assert %IR.MatchOperator{
               left: %IR.MapType{
                 data: [
                   {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x}},
                   {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                   {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
                 ]
               },
               right: _right
             } = transform_module_and_fetch_expr(Module107)
    end

    test "without cons operator, in pattern, with match placeholder instead of module (AST from source code)" do
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

    test "without cons operator, in pattern, with match placeholder instead of module (AST from BEAM file)" do
      assert %IR.MatchOperator{
               left: %IR.MapType{
                 data: [
                   {%IR.AtomType{value: :__struct__}, %IR.MatchPlaceholder{}},
                   {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                   {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
                 ]
               },
               right: _right
             } = transform_module_and_fetch_expr(Module108)
    end

    # Case not possible, since it wouldn't compile:
    # test "without cons operator, not in pattern, with match placeholder instead of module"

    test "with cons operator, not in pattern (AST from source code)" do
      ast = ast("%Hologram.Test.Fixtures.Compiler.Tranformer.Module109{x | a: 1, b: 2}")

      context = %Context{pattern?: false}

      assert transform(ast, context) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x},
                 %IR.RemoteFunctionCall{
                   module: %IR.AtomType{value: Module109},
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

    test "with cons operator, not in pattern (AST from BEAM file)" do
      assert transform_module_and_fetch_expr(Module109) == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: Map},
               function: :merge,
               args: [
                 %IR.Variable{name: :x, version: 0},
                 %IR.RemoteFunctionCall{
                   module: %IR.AtomType{value: Module109},
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

  describe "try (explicit)" do
    test "body (AST from source code)" do
      ast =
        ast("""
        try do
          x = 1
          x
        rescue
          e -> {e, :ok}
        end
        """)

      assert %IR.Try{
               body: %IR.Block{
                 expressions: [
                   %IR.MatchOperator{
                     left: %IR.Variable{name: :x},
                     right: %IR.IntegerType{value: 1}
                   },
                   %IR.Variable{name: :x}
                 ]
               }
             } = transform(ast, %Context{})
    end

    test "body (AST from BEAM file)" do
      assert %IR.Try{
               body: %IR.Block{
                 expressions: [
                   %IR.MatchOperator{
                     left: %IR.Variable{name: :x},
                     right: %IR.IntegerType{value: 1}
                   },
                   %IR.Variable{name: :x}
                 ]
               }
             } = transform_module_and_fetch_expr(Module110)
    end

    test "rescue clause with single module / single rescue clause (AST from source code)" do
      ast =
        ast("""
        try do
          1
        rescue
          RuntimeError -> :ok
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: nil,
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with single module / single rescue clause (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.MatchPlaceholder{},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module111)
    end

    test "rescue clause with multiple modules (AST from source code)" do
      ast =
        ast("""
        try do
          1
        rescue
          [ArgumentError, RuntimeError] -> :ok
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: nil,
                   modules: [
                     %IR.AtomType{value: ArgumentError},
                     %IR.AtomType{value: RuntimeError}
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with multiple modules (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.MatchPlaceholder{},
                   modules: [
                     %IR.AtomType{value: ArgumentError},
                     %IR.AtomType{value: RuntimeError}
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module112)
    end

    test "rescue clause with variable (AST from source code)" do
      ast =
        ast("""
        try do
          1
        rescue
          e -> {e, :ok}
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with variable (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module116)
    end

    test "rescue clause with variable and single module (AST from source code)" do
      ast =
        ast("""
        try do
          1
        rescue
          e in [RuntimeError] -> {e, :ok}
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with variable and single module (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module118)
    end

    test "rescue clause with variable and multiple modules (AST from source code)" do
      ast =
        ast("""
        try do
          1
        rescue
          e in [ArgumentError, RuntimeError] -> {e, :ok}
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [
                     %IR.AtomType{value: ArgumentError},
                     %IR.AtomType{value: RuntimeError}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "rescue clause with variable and multiple modules (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [
                     %IR.AtomType{value: ArgumentError},
                     %IR.AtomType{value: RuntimeError}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module120)
    end

    test "multiple rescue clauses (AST from source code)" do
      ast =
        ast("""
        try do
          1
        rescue
          x in [ArgumentError] -> {x, :ok}
          y in [RuntimeError] -> {y, :ok}
        end
        """)

      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [%IR.AtomType{value: ArgumentError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :x}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 },
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :y},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :y}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple rescue clauses (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [%IR.AtomType{value: ArgumentError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :x}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 },
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :y},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :y}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module122)
    end

    test "catch clause with value / single catch clause (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          e -> {e, :ok}
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :e},
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value / single catch clause (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :e},
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module124)
    end

    test "catch clause with value and single guard (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          x when is_integer(x) -> :ok
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value and single guard (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module126)
    end

    test "catch clause with value and 2 guards (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          x when is_integer(x) when x > 1 -> :ok
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value and 2 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module128)
    end

    test "catch clause with value and 3 guards (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          x when is_integer(x) when x > 1 when x < 9 -> :ok
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with value and 3 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module130)
    end

    test "catch clause with kind and value (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          :exit, :timeout -> :error
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :exit},
                   value: %IR.AtomType{value: :timeout},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :error}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind and value (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :exit},
                   value: %IR.AtomType{value: :timeout},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :error}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module132)
    end

    test "catch clause with kind, value and single guard (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          :error, x when is_integer(x) -> :ok
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind, value and single guard (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module134)
    end

    test "catch clause with kind, value and 2 guards (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          :error, x when is_integer(x) when x > 1 -> :ok
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind, value and 2 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module136)
    end

    test "catch clause with kind, value and 3 guards (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          :error, x when is_integer(x) when x > 1 when x < 9 -> :ok
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "catch clause with kind, value and 3 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module138)
    end

    test "multiple catch clauses (AST from source code)" do
      ast =
        ast("""
        try do
          1
        catch
          :error -> :a
          :warning -> :b
        end
        """)

      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.AtomType{value: :error},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :a}]
                   }
                 },
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.AtomType{value: :warning},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple catch clauses (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.AtomType{value: :error},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :a}]
                   }
                 },
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.AtomType{value: :warning},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module140)
    end

    test "single else clause (AST from source code)" do
      ast =
        ast("""
        try do
          x
        catch
          :error -> :a
        else
          :b -> :c
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "single else clause (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module142)
    end

    test "multiple else clauses (AST from source code)" do
      ast =
        ast("""
        try do
          x
        catch
          :error -> :a
        else
          :b -> :c
          :d -> :e
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.AtomType{value: :d},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :e}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "multiple else clauses (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.AtomType{value: :d},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :e}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module144)
    end

    test "else clause with single guard (AST from source code)" do
      ast =
        ast("""
        try do
          x
        catch
          :error -> :a
        else
          y when is_integer(y) -> :b
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "else clause with single guard (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module146)
    end

    test "else clause with 2 guard (AST from source code)" do
      ast =
        ast("""
        try do
          x
        catch
          :error -> :a
        else
          y when is_integer(y) when y > 1 -> :b
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "else clause with 2 guard (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module148)
    end

    test "else clause with 3 guards (AST from source code)" do
      ast =
        ast("""
        try do
          x
        catch
          :error -> :a
        else
          y when is_integer(y) when y > 1 when y < 9 -> :b
        end
        """)

      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.LocalFunctionCall{
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     },
                     %IR.LocalFunctionCall{
                       function: :>,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 1}]
                     },
                     %IR.LocalFunctionCall{
                       function: :<,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform(ast, %Context{})
    end

    test "else clause with 3 guards (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module150)
    end

    test "after block (AST from source code)" do
      ast =
        ast("""
        try do
          1
        after
          x = 1
          x
        end
        """)

      assert %IR.Try{
               after_block: %IR.Block{
                 expressions: [
                   %IR.MatchOperator{
                     left: %IR.Variable{name: :x},
                     right: %IR.IntegerType{value: 1}
                   },
                   %IR.Variable{name: :x}
                 ]
               }
             } = transform(ast, %Context{})
    end

    test "after block (AST from BEAM file)" do
      assert %IR.Try{
               after_block: %IR.Block{
                 expressions: [
                   %IR.MatchOperator{
                     left: %IR.Variable{name: :x},
                     right: %IR.IntegerType{value: 1}
                   },
                   %IR.Variable{name: :x}
                 ]
               }
             } = transform_module_and_fetch_expr(Module152)
    end
  end

  # Hologram doesn't support transforming of non-expanded AST of implicit try expressions
  # (such AST would be returned by the ast/1 test helper function).
  # BEAM files contain already expanded AST.
  describe "try (implicit)" do
    test "body (AST from BEAM file)" do
      assert %IR.Try{
               body: %IR.Block{
                 expressions: [
                   %IR.MatchOperator{
                     left: %IR.Variable{name: :x},
                     right: %IR.IntegerType{value: 1}
                   },
                   %IR.Variable{name: :x}
                 ]
               }
             } = transform_module_and_fetch_expr(Module113)
    end

    test "rescue clause with single module / single rescue clause (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.MatchPlaceholder{},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module114)
    end

    test "rescue clause with multiple modules (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.MatchPlaceholder{},
                   modules: [
                     %IR.AtomType{value: ArgumentError},
                     %IR.AtomType{value: RuntimeError}
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module115)
    end

    test "rescue clause with variable (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module117)
    end

    test "rescue clause with variable and single module (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module119)
    end

    test "rescue clause with variable and multiple modules (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :e},
                   modules: [
                     %IR.AtomType{value: ArgumentError},
                     %IR.AtomType{value: RuntimeError}
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module121)
    end

    test "multiple rescue clauses (AST from BEAM file)" do
      assert %IR.Try{
               rescue_clauses: [
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :x},
                   modules: [%IR.AtomType{value: ArgumentError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :x}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 },
                 %IR.TryRescueClause{
                   variable: %IR.Variable{name: :y},
                   modules: [%IR.AtomType{value: RuntimeError}],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :y}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module123)
    end

    test "catch clause with value / single catch clause (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :e},
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.TupleType{data: [%IR.Variable{name: :e}, %IR.AtomType{value: :ok}]}
                     ]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module125)
    end

    test "catch clause with value and single guard (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module127)
    end

    test "catch clause with value and 2 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module129)
    end

    test "catch clause with value and 3 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module131)
    end

    test "catch clause with kind and value (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :exit},
                   value: %IR.AtomType{value: :timeout},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :error}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module133)
    end

    test "catch clause with kind, value and single guard (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :x}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module135)
    end

    test "catch clause with kind, value and 2 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module137)
    end

    test "catch clause with kind, value and 3 guards (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :error},
                   value: %IR.Variable{name: :x},
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
                     expressions: [%IR.AtomType{value: :ok}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module139)
    end

    test "multiple catch clauses (AST from BEAM file)" do
      assert %IR.Try{
               catch_clauses: [
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.AtomType{value: :error},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :a}]
                   }
                 },
                 %IR.TryCatchClause{
                   kind: %IR.AtomType{value: :throw},
                   value: %IR.AtomType{value: :warning},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module141)
    end

    test "single else clause (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module143)
    end

    test "multiple else clauses (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.AtomType{value: :b},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :c}]
                   }
                 },
                 %IR.Clause{
                   match: %IR.AtomType{value: :d},
                   guards: [],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :e}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module145)
    end

    test "else clause with single guard (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module147)
    end

    test "else clause with 2 guard (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 1}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module149)
    end

    test "else clause with 3 guards (AST from BEAM file)" do
      assert %IR.Try{
               else_clauses: [
                 %IR.Clause{
                   match: %IR.Variable{name: :y},
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_integer,
                       args: [%IR.Variable{name: :y}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :>,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 1}]
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :<,
                       args: [%IR.Variable{name: :y}, %IR.IntegerType{value: 9}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [%IR.AtomType{value: :b}]
                   }
                 }
               ]
             } = transform_module_and_fetch_expr(Module151)
    end

    test "after block (AST from BEAM file)" do
      assert %IR.Try{
               after_block: %IR.Block{
                 expressions: [
                   %IR.MatchOperator{
                     left: %IR.Variable{name: :x},
                     right: %IR.IntegerType{value: 1}
                   },
                   %IR.Variable{name: :x}
                 ]
               }
             } = transform_module_and_fetch_expr(Module153)
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
