defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  describe "anonymous function type" do
    test "with single clause" do
      ir = %IR.AnonymousFunctionType{
        arity: 2,
        clauses: [
          %IR.FunctionClause{
            params: [%IR.Variable{name: :x}],
            guard: nil,
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :expr}]
            }
          }
        ]
      }

      assert encode(ir, %Context{}) == """
             Type.anonymousFunction(2, [{params: [Type.variablePattern("x")], guard: null, body: (vars) => {
             return Type.atom("expr");
             }}], vars)\
             """
    end

    test "with multiple clauses" do
      ir = %IR.AnonymousFunctionType{
        arity: 2,
        clauses: [
          %IR.FunctionClause{
            params: [%IR.Variable{name: :x}],
            guard: nil,
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :expr_a}]
            }
          },
          %IR.FunctionClause{
            params: [%IR.Variable{name: :y}],
            guard: nil,
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :expr_b}]
            }
          }
        ]
      }

      assert encode(ir, %Context{}) == """
             Type.anonymousFunction(2, [{params: [Type.variablePattern("x")], guard: null, body: (vars) => {
             return Type.atom("expr_a");
             }}, {params: [Type.variablePattern("y")], guard: null, body: (vars) => {
             return Type.atom("expr_b");
             }}], vars)\
             """
    end
  end

  describe "atom type" do
    test "nil" do
      ir = %IR.AtomType{value: nil}

      assert encode(ir, %Context{}) == ~s/Type.atom("nil")/
    end

    test "false" do
      ir = %IR.AtomType{value: false}

      assert encode(ir, %Context{}) == ~s/Type.atom("false")/
    end

    test "true" do
      ir = %IR.AtomType{value: true}

      assert encode(ir, %Context{}) == ~s/Type.atom("true")/
    end

    test "non-nil and non-boolean" do
      ir = %IR.AtomType{value: :"aa\"bb\ncc"}

      assert encode(ir, %Context{}) == ~s/Type.atom("aa\\"bb\\ncc")/
    end
  end

  describe "bitstring" do
    test "no segments" do
      ir = %IR.BitstringType{segments: []}

      assert encode(ir, %Context{}) == "Type.bitstring([])"
    end

    test "single segment" do
      ir = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 1},
            modifiers: []
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "Type.bitstring([Type.bitstringSegment(Type.integer(1n), {})])"
    end

    test "multiple segments" do
      ir = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 1},
            modifiers: []
          },
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 2},
            modifiers: []
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "Type.bitstring([Type.bitstringSegment(Type.integer(1n), {}), Type.bitstringSegment(Type.integer(2n), {})])"
    end
  end

  describe "bitstring segment" do
    test "no modifiers specified" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: []
      }

      assert encode(ir, %Context{}) == "Type.bitstringSegment(Type.integer(123n), {})"
    end

    test "all modifiers specified" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [
          type: :integer,
          size: %IR.IntegerType{value: 16},
          unit: 1,
          signedness: :signed,
          endianness: :big
        ]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {type: "integer", size: Type.integer(16n), unit: 1n, signedness: "signed", endianness: "big"})/
    end

    test "single modifier specified" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [endianness: :big]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {endianness: "big"})/
    end

    test "from string type" do
      ir = %IR.BitstringSegment{value: %IR.StringType{value: "abc"}, modifiers: [type: "utf16"]}

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.string(\"abc\"), {type: "utf16"})/
    end

    test "from non-string type" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [endianness: :big]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {endianness: "big"})/
    end
  end

  describe "block" do
    test "empty" do
      ir = %IR.Block{expressions: []}

      assert encode(ir, %Context{}) ==
               """
               {
               return Type.atom("nil");
               }\
               """
    end

    test "single expression" do
      ir = %IR.Block{
        expressions: [
          %IR.IntegerType{value: 1}
        ]
      }

      assert encode(ir, %Context{}) ==
               """
               {
               return Type.integer(1n);
               }\
               """
    end

    test "multiple expressions" do
      ir = %IR.Block{
        expressions: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }

      assert encode(ir, %Context{}) ==
               """
               {
               Type.integer(1n);
               return Type.integer(2n);
               }\
               """
    end
  end

  test "case" do
    clause_1 = %IR.CaseClause{
      head: %IR.Variable{name: :x},
      guard: nil,
      body: %IR.Block{
        expressions: [
          %IR.AtomType{value: :expr_1}
        ]
      }
    }

    clause_2 = %IR.CaseClause{
      head: %IR.Variable{name: :y},
      guard: nil,
      body: %IR.Block{
        expressions: [
          %IR.AtomType{value: :expr_2}
        ]
      }
    }

    ir = %IR.Case{
      condition: %IR.IntegerType{value: 123},
      clauses: [clause_1, clause_2]
    }

    assert encode(ir, %Context{}) == """
           Interpreter.case(Type.integer(123n), [{head: Type.variablePattern("x"), guard: null, body: (vars) => {
           return Type.atom("expr_1");
           }}, {head: Type.variablePattern("y"), guard: null, body: (vars) => {
           return Type.atom("expr_2");
           }}])\
           """
  end

  test "case clause" do
    ir = %IR.CaseClause{
      head: %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.Variable{name: :x}
        ]
      },
      guard: %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :<,
        args: [
          %IR.Variable{name: :x},
          %IR.IntegerType{value: 3}
        ]
      },
      body: %IR.Block{
        expressions: [
          %IR.IntegerType{value: 11},
          %IR.IntegerType{value: 12}
        ]
      }
    }

    assert encode(ir, %Context{}) == """
           {head: Type.tuple([Type.integer(1n), Type.variablePattern("x")]), guard: (vars) => Erlang.$260(vars.x, Type.integer(3n)), body: (vars) => {
           Type.integer(11n);
           return Type.integer(12n);
           }}\
           """
  end

  test "comprehension" do
    # for x when x < 3 <- [1, 2],
    #     y when y < 5 <- [3, 4],
    #     is_integer(x),
    #     is_integer(y),
    #     into: %{},
    #     uniq: true,
    #     do: {x, y}
    #
    # for x when :erlang.<(x, 3) <- [1, 2],
    #     y when :erlang.<(y, 5) <- [3, 4],
    #     :erlang.is_integer(x),
    #     :erlang.is_integer(y),
    #     into: %{},
    #     uniq: true,
    #     do: {x, y}

    ir = %IR.Comprehension{
      generators: [
        %IR.ComprehensionGenerator{
          enumerable: %IR.ListType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.IntegerType{value: 2}
            ]
          },
          match: %IR.Variable{name: :x},
          guard: %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :<,
            args: [
              %IR.Variable{name: :x},
              %IR.IntegerType{value: 3}
            ]
          }
        },
        %IR.ComprehensionGenerator{
          enumerable: %IR.ListType{
            data: [
              %IR.IntegerType{value: 3},
              %IR.IntegerType{value: 4}
            ]
          },
          match: %IR.Variable{name: :y},
          guard: %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :<,
            args: [
              %IR.Variable{name: :y},
              %IR.IntegerType{value: 5}
            ]
          }
        }
      ],
      filters: [
        %IR.ComprehensionFilter{
          expression: %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :is_integer,
            args: [%IR.Variable{name: :x}]
          }
        },
        %IR.ComprehensionFilter{
          expression: %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :is_integer,
            args: [%IR.Variable{name: :y}]
          }
        }
      ],
      collectable: %IR.MapType{data: []},
      unique: %IR.AtomType{value: true},
      mapper: %IR.TupleType{
        data: [
          %IR.Variable{name: :x},
          %IR.Variable{name: :y}
        ]
      }
    }

    assert encode(ir, %Context{}) ==
             "Interpreter.comprehension([{enumerable: Type.list([Type.integer(1n), Type.integer(2n)]), match: Type.variablePattern(\"x\"), guard: (vars) => Erlang.$260(vars.x, Type.integer(3n))}, {enumerable: Type.list([Type.integer(3n), Type.integer(4n)]), match: Type.variablePattern(\"y\"), guard: (vars) => Erlang.$260(vars.y, Type.integer(5n))}], [(vars) => Erlang.is_integer(vars.x), (vars) => Erlang.is_integer(vars.y)], Type.map([]), true, (vars) => Type.tuple([vars.x, vars.y]), vars)"
  end

  test "comprehension filter" do
    ir = %IR.ComprehensionFilter{
      expression: %IR.LocalFunctionCall{
        function: :my_filter,
        args: [%IR.Variable{name: :a}]
      }
    }

    assert encode(ir, %Context{module: MyModule}) == "(vars) => Elixir_MyModule.my_filter(vars.a)"
  end

  test "comprehension generator" do
    ir = %IR.ComprehensionGenerator{
      enumerable: %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      },
      match: %IR.TupleType{
        data: [
          %IR.Variable{name: :a},
          %IR.Variable{name: :b}
        ]
      },
      guard: %IR.LocalFunctionCall{
        function: :my_guard,
        args: [
          %IR.Variable{name: :a},
          %IR.IntegerType{value: 2}
        ]
      }
    }

    assert encode(ir, %Context{module: MyModule}) ==
             "{enumerable: Type.list([Type.integer(1n), Type.integer(2n)]), match: Type.tuple([Type.variablePattern(\"a\"), Type.variablePattern(\"b\")]), guard: (vars) => Elixir_MyModule.my_guard(vars.a, Type.integer(2n))}"
  end

  test "cond" do
    clause_1 = %IR.CondClause{
      condition: %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :<,
        args: [
          %IR.Variable{name: :x},
          %IR.IntegerType{value: 1}
        ]
      },
      body: %IR.Block{
        expressions: [
          %IR.IntegerType{value: 1}
        ]
      }
    }

    clause_2 = %IR.CondClause{
      condition: %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :<,
        args: [
          %IR.Variable{name: :x},
          %IR.IntegerType{value: 2}
        ]
      },
      body: %IR.Block{
        expressions: [
          %IR.IntegerType{value: 2}
        ]
      }
    }

    ir = %IR.Cond{clauses: [clause_1, clause_2]}

    assert encode(ir, %Context{}) == """
           Interpreter.cond([{condition: (vars) => Erlang.$260(vars.x, Type.integer(1n)), body: (vars) => {
           return Type.integer(1n);
           }}, {condition: (vars) => Erlang.$260(vars.x, Type.integer(2n)), body: (vars) => {
           return Type.integer(2n);
           }}])\
           """
  end

  test "cond clause" do
    ir = %IR.CondClause{
      condition: %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :<,
        args: [
          %IR.Variable{name: :x},
          %IR.IntegerType{value: 3}
        ]
      },
      body: %IR.Block{
        expressions: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }
    }

    assert encode(ir, %Context{}) == """
           {condition: (vars) => Erlang.$260(vars.x, Type.integer(3n)), body: (vars) => {
           Type.integer(1n);
           return Type.integer(2n);
           }}\
           """
  end

  describe "cons operator" do
    @cons_operator_ir %IR.ConsOperator{
      head: %IR.IntegerType{value: 1},
      tail: %IR.ListType{data: [%IR.IntegerType{value: 2}, %IR.IntegerType{value: 3}]}
    }

    test "not inside pattern" do
      assert encode(@cons_operator_ir, %Context{pattern?: false}) ==
               "Interpreter.consOperator(Type.integer(1n), Type.list([Type.integer(2n), Type.integer(3n)])))"
    end

    test "inside pattern" do
      assert encode(@cons_operator_ir, %Context{pattern?: true}) ==
               "Type.consPattern(Type.integer(1n), Type.list([Type.integer(2n), Type.integer(3n)]))"
    end
  end

  test "dot operator" do
    ir = %IR.DotOperator{
      left: %IR.Variable{name: :my_module},
      right: %IR.AtomType{value: :my_key}
    }

    assert encode(ir, %Context{}) ==
             "Interpreter.dotOperator(vars.my_module, Type.atom(\"my_key\"))"
  end

  test "float type" do
    assert encode(%IR.FloatType{value: 1.23}, %Context{}) == "Type.float(1.23)"
  end

  describe "function clause" do
    test "without guard" do
      ir = %IR.FunctionClause{
        params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
        guard: nil,
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
        }
      }

      assert encode(ir, %Context{}) == """
             {params: [Type.variablePattern("x"), Type.variablePattern("y")], guard: null, body: (vars) => {
             Type.atom("expr_1");
             return Type.atom("expr_2");
             }}\
             """
    end

    test "with guard" do
      ir = %IR.FunctionClause{
        params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
        guard: %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: :erlang},
          function: :is_integer,
          args: [%IR.Variable{name: :x}]
        },
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
        }
      }

      assert encode(ir, %Context{}) == """
             {params: [Type.variablePattern("x"), Type.variablePattern("y")], guard: (vars) => Erlang.is_integer(vars.x), body: (vars) => {
             Type.atom("expr_1");
             return Type.atom("expr_2");
             }}\
             """
    end
  end

  test "integer type" do
    assert encode(%IR.IntegerType{value: 123}, %Context{}) == "Type.integer(123n)"
  end

  describe "list type" do
    test "empty" do
      assert encode(%IR.ListType{data: []}, %Context{}) == "Type.list([])"
    end

    test "non-empty" do
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir, %Context{}) == ~s/Type.list([Type.integer(1n), Type.atom("abc")])/
    end
  end

  test "local function call" do
    ir = %IR.LocalFunctionCall{
      function: :my_fun!,
      args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    }

    assert encode(ir, %Context{module: Aaa.Bbb.Ccc}) ==
             "Elixir_Aaa_Bbb_Ccc.my_fun$233(Type.integer(1n), Type.integer(2n))"
  end

  describe "map type" do
    test "empty" do
      assert encode(%IR.MapType{data: []}, %Context{}) == "Type.map([])"
    end

    test "single key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.AtomType{value: :a},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) == ~s/Type.map([[Type.atom("a"), Type.integer(1n)]])/
    end

    test "multiple keys" do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.map([[Type.atom("a"), Type.integer(1n)], [Type.atom("b"), Type.integer(2n)]])/
    end
  end

  describe "match operator" do
    test "literal value on both sides" do
      # 1 = 2
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.IntegerType{value: 2}
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1n), Type.integer(2n), vars)"
    end

    test "variable in pattern" do
      # x = 2
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.IntegerType{value: 2}
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator(Type.variablePattern("x"), Type.integer(2n), vars)/
    end

    test "variable in expression" do
      # 1 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.Variable{name: :x}
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1n), vars.x, vars)"
    end

    test "nested, variable in pattern" do
      # x = 2 = 3
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator(Type.variablePattern("x"), Interpreter.matchOperator(Type.integer(2n), Type.integer(3n), vars), vars)/
    end

    test "nested, variable in the middle" do
      # 1 = x = 3
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.Variable{name: :x},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator(Type.integer(1n), Interpreter.matchOperator(Type.variablePattern("x"), Type.integer(3n), vars), vars)/
    end

    test "nested, variable in expression" do
      # 1 = 2 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.Variable{name: :x}
        }
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1n), Interpreter.matchOperator(Type.integer(2n), vars.x, vars), vars)"
    end

    test "nested multiple-times" do
      # {a = b, 2, 3} = {1, c = d, 3} = {1, 2, e = f}
      ir = %IR.MatchOperator{
        left: %IR.TupleType{
          data: [
            %IR.MatchOperator{
              left: %IR.Variable{name: :a},
              right: %IR.Variable{name: :b}
            },
            %IR.IntegerType{value: 2},
            %IR.IntegerType{value: 3}
          ]
        },
        right: %IR.MatchOperator{
          left: %IR.TupleType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.MatchOperator{
                left: %IR.Variable{name: :c},
                right: %IR.Variable{name: :d}
              },
              %IR.IntegerType{value: 3}
            ]
          },
          right: %IR.TupleType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.IntegerType{value: 2},
              %IR.MatchOperator{
                left: %IR.Variable{name: :e},
                right: %IR.Variable{name: :f}
              }
            ]
          }
        }
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator(Type.tuple([Interpreter.matchOperator(Type.variablePattern("a"), Type.variablePattern("b"), vars), Type.integer(2n), Type.integer(3n)]), Interpreter.matchOperator(Type.tuple([Type.integer(1n), Interpreter.matchOperator(Type.variablePattern("c"), Type.variablePattern("d"), vars), Type.integer(3n)]), Type.tuple([Type.integer(1n), Type.integer(2n), Interpreter.matchOperator(Type.variablePattern("e"), vars.f, vars)]), vars), vars)/
    end
  end

  test "match placeholder" do
    assert encode(%IR.MatchPlaceholder{}, %Context{}) == "Type.matchPlaceholder()"
  end

  test "module attribute operator" do
    assert encode(%IR.ModuleAttributeOperator{name: :abc?}, %Context{}) == "vars.$264abc$263"
  end

  test "module definition" do
    # defmodule Aaa.Bbb do
    #   def fun_1(a, b) do
    #     :erlang.+(a, b)
    #   end

    #   def fun_1(c) when :erlang.is_integer(c), do: c

    #   defp fun_2(x, y) do
    #     :erlang.*(x, y)
    #   end

    #   defp fun_2(z) when :erlang.is_float(z), do: z
    # end
    ir = %IR.ModuleDefinition{
      module: %IR.AtomType{value: Aaa.Bbb},
      body: %IR.Block{
        expressions: [
          %IR.FunctionDefinition{
            name: :fun_1,
            arity: 2,
            visibility: :public,
            clause: %IR.FunctionClause{
              params: [
                %IR.Variable{name: :a},
                %IR.Variable{name: :b}
              ],
              guard: nil,
              body: %IR.Block{
                expressions: [
                  %IR.RemoteFunctionCall{
                    module: %IR.AtomType{value: :erlang},
                    function: :+,
                    args: [
                      %IR.Variable{name: :a},
                      %IR.Variable{name: :b}
                    ]
                  }
                ]
              }
            }
          },
          %IR.FunctionDefinition{
            name: :fun_1,
            arity: 1,
            visibility: :public,
            clause: %IR.FunctionClause{
              params: [%IR.Variable{name: :c}],
              guard: %IR.RemoteFunctionCall{
                module: %IR.AtomType{value: :erlang},
                function: :is_integer,
                args: [%IR.Variable{name: :c}]
              },
              body: %IR.Block{
                expressions: [%IR.Variable{name: :c}]
              }
            }
          },
          %IR.FunctionDefinition{
            name: :fun_2,
            arity: 2,
            visibility: :private,
            clause: %IR.FunctionClause{
              params: [
                %IR.Variable{name: :x},
                %IR.Variable{name: :y}
              ],
              guard: nil,
              body: %IR.Block{
                expressions: [
                  %IR.RemoteFunctionCall{
                    module: %IR.AtomType{value: :erlang},
                    function: :*,
                    args: [
                      %IR.Variable{name: :x},
                      %IR.Variable{name: :y}
                    ]
                  }
                ]
              }
            }
          },
          %IR.FunctionDefinition{
            name: :fun_2,
            arity: 1,
            visibility: :private,
            clause: %IR.FunctionClause{
              params: [%IR.Variable{name: :z}],
              guard: %IR.RemoteFunctionCall{
                module: %IR.AtomType{value: :erlang},
                function: :is_float,
                args: [%IR.Variable{name: :z}]
              },
              body: %IR.Block{
                expressions: [%IR.Variable{name: :z}]
              }
            }
          }
        ]
      }
    }

    assert encode(ir, %Context{}) == """


           Interpreter.defineFunction("Elixir_Aaa_Bbb", "fun_1", [{params: [Type.variablePattern("a"), Type.variablePattern("b")], guard: null, body: (vars) => {
           return Erlang.$243(vars.a, vars.b);
           }}, {params: [Type.variablePattern("c")], guard: (vars) => Erlang.is_integer(vars.c), body: (vars) => {
           return vars.c;
           }}])

           Interpreter.defineFunction("Elixir_Aaa_Bbb", "fun_2", [{params: [Type.variablePattern("x"), Type.variablePattern("y")], guard: null, body: (vars) => {
           return Erlang.$242(vars.x, vars.y);
           }}, {params: [Type.variablePattern("z")], guard: (vars) => Erlang.is_float(vars.z), body: (vars) => {
           return vars.z;
           }}])\
           """
  end

  test "pin operator" do
    assert encode(%IR.PinOperator{name: :abc}, %Context{}) == "vars.abc"
  end

  describe "remote function call" do
    test "called on a module alias" do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Aaa.Bbb.Ccc},
        function: :my_fun!,
        args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
      }

      assert encode(ir, %Context{}) ==
               "Elixir_Aaa_Bbb_Ccc.my_fun$233(Type.integer(1n), Type.integer(2n))"
    end

    test "called on variable" do
      ir = %IR.RemoteFunctionCall{
        module: %IR.Variable{name: :x},
        function: :my_fun!,
        args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
      }

      assert encode(ir, %Context{}) == "vars.x.my_fun$233(Type.integer(1n), Type.integer(2n))"
    end
  end

  test "string type" do
    ir = %IR.StringType{value: "aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.bitstring("aa\\"bb\\ncc")/
  end

  describe "tuple type" do
    test "empty" do
      assert encode(%IR.TupleType{data: []}, %Context{}) == "Type.tuple([])"
    end

    test "non-empty" do
      ir = %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir, %Context{}) == ~s/Type.tuple([Type.integer(1n), Type.atom("abc")])/
    end
  end

  describe "variable" do
    test "not inside pattern" do
      assert encode(%IR.Variable{name: :my_var}, %Context{pattern?: false}) == "vars.my_var"
    end

    test "inside pattern" do
      assert encode(%IR.Variable{name: :my_var}, %Context{pattern?: true}) ==
               ~s/Type.variablePattern("my_var")/
    end

    test "escape" do
      assert encode(%IR.Variable{name: :my_var?}, %Context{}) == "vars.my_var$263"
    end
  end

  describe "encode_as_class_name/1" do
    test "encodes module alias having lowercase starting letter" do
      assert encode_as_class_name(:mymodule) == "Erlang_Mymodule"
    end

    test "encodes module alias not having lowercase starting letter" do
      assert encode_as_class_name(Aaa.Bbb.Ccc) == "Elixir_Aaa_Bbb_Ccc"
    end

    test "encodes :erlang module alias" do
      assert encode_as_class_name(:erlang) == "Erlang"
    end
  end

  describe "escape_js_identifier/1" do
    test "escape characters which are not allowed in JS identifiers" do
      assert escape_js_identifier("@[^`{") == "$264$291$294$296$3123"
    end

    test "escape $ (dollar sign) character" do
      assert escape_js_identifier("$") == "$236"
    end

    test "does not escape characters which are allowed in JS identifiers" do
      str = "059AKZakz_"
      assert escape_js_identifier(str) == str
    end
  end
end
