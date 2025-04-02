defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder, except: [encode_ir: 2]

  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  defdelegate encode_ir(ir, context \\ %Context{}), to: Hologram.Compiler.Encoder

  @erlang_source_dir Path.join([Reflection.root_dir(), "assets", "js", "erlang"])

  test "anonymous function call" do
    # my_fun.(1, 2)
    ir = %IR.AnonymousFunctionCall{
      function: %IR.Variable{name: :my_fun},
      args: [
        %IR.IntegerType{value: 1},
        %IR.IntegerType{value: 2}
      ]
    }

    assert encode_ir(ir) ==
             "Interpreter.callAnonymousFunction(context.vars.my_fun, [Type.integer(1n), Type.integer(2n)])"
  end

  describe "anonymous function type" do
    test "with single clause" do
      # fn x -> :expr end
      ir = %IR.AnonymousFunctionType{
        arity: 1,
        captured_module: nil,
        captured_function: nil,
        clauses: [
          %IR.FunctionClause{
            params: [%IR.Variable{name: :x}],
            guards: [],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :expr}]
            }
          }
        ]
      }

      assert encode_ir(ir) == """
             Type.anonymousFunction(1, [{params: (context) => [Type.variablePattern("x")], guards: [], body: (context) => {
             return Type.atom("expr");
             }}], context)\
             """
    end

    test "with multiple clauses" do
      # fn
      #   x -> :expr_a
      #   y -> :expr_b
      # end
      ir = %IR.AnonymousFunctionType{
        arity: 1,
        captured_module: nil,
        captured_function: nil,
        clauses: [
          %IR.FunctionClause{
            params: [%IR.Variable{name: :x}],
            guards: [],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :expr_a}]
            }
          },
          %IR.FunctionClause{
            params: [%IR.Variable{name: :y}],
            guards: [],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :expr_b}]
            }
          }
        ]
      }

      assert encode_ir(ir) == """
             Type.anonymousFunction(1, [{params: (context) => [Type.variablePattern("x")], guards: [], body: (context) => {
             return Type.atom("expr_a");
             }}, {params: (context) => [Type.variablePattern("y")], guards: [], body: (context) => {
             return Type.atom("expr_b");
             }}], context)\
             """
    end

    test "with Elixir module/function capture info" do
      # credo:disable-for-lines:27 Credo.Check.Design.DuplicatedCode
      # &Calendar.ISO.parse_date/2
      ir = %IR.AnonymousFunctionType{
        arity: 2,
        captured_module: Calendar.ISO,
        captured_function: :parse_date,
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

      assert encode_ir(ir) == """
             Type.functionCapture("Calendar.ISO", "parse_date", 2, [{params: (context) => [Type.variablePattern("$1"), Type.variablePattern("$2")], guards: [], body: (context) => {
             return Elixir_Calendar_ISO["parse_date/2"](context.vars["$1"], context.vars["$2"]);
             }}], context)\
             """
    end

    test "with Erlang module/function capture info" do
      # &:persistent_term.get/2
      ir = %IR.AnonymousFunctionType{
        arity: 2,
        captured_module: :persistent_term,
        captured_function: :get,
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
                  module: %IR.AtomType{value: :persistent_term},
                  function: :get,
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

      assert encode_ir(ir) == """
             Type.functionCapture(":persistent_term", "get", 2, [{params: (context) => [Type.variablePattern("$1"), Type.variablePattern("$2")], guards: [], body: (context) => {
             return Erlang_Persistent_Term["get/2"](context.vars["$1"], context.vars["$2"]);
             }}], context)\
             """
    end
  end

  describe "atom type" do
    test "nil" do
      # nil
      ir = %IR.AtomType{value: nil}

      assert encode_ir(ir) == ~s/Type.atom("nil")/
    end

    test "false" do
      # false
      ir = %IR.AtomType{value: false}

      assert encode_ir(ir) == ~s/Type.atom("false")/
    end

    test "true" do
      # true
      ir = %IR.AtomType{value: true}

      assert encode_ir(ir) == ~s/Type.atom("true")/
    end

    test "non-nil and non-boolean" do
      # :"aa\"bb\ncc"
      ir = %IR.AtomType{value: :"aa\"bb\ncc"}

      assert encode_ir(ir) == ~s/Type.atom("aa\\"bb\\ncc")/
    end
  end

  describe "bitstring pattern" do
    @context %Context{pattern?: true}

    test "no segments" do
      # <<>>
      ir = %IR.BitstringType{segments: []}

      assert encode_ir(ir, @context) == "Type.bitstringPattern([])"
    end

    test "single segment" do
      # <<1>>
      ir = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 1},
            modifiers: []
          }
        ]
      }

      assert encode_ir(ir, @context) ==
               "Type.bitstringPattern([Type.bitstringSegment(Type.integer(1n), {})])"
    end

    test "multiple segments" do
      # <<1, 2>>
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

      assert encode_ir(ir, @context) ==
               "Type.bitstringPattern([Type.bitstringSegment(Type.integer(1n), {}), Type.bitstringSegment(Type.integer(2n), {})])"
    end
  end

  describe "bitstring type" do
    @context %Context{pattern?: false}

    test "no segments" do
      # <<>>
      ir = %IR.BitstringType{segments: []}

      assert encode_ir(ir, @context) == "Type.bitstring([])"
    end

    test "single segment" do
      # <<1>>
      ir = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 1},
            modifiers: []
          }
        ]
      }

      assert encode_ir(ir, @context) ==
               "Type.bitstring([Type.bitstringSegment(Type.integer(1n), {})])"
    end

    test "multiple segments" do
      # <<1, 2>>
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

      assert encode_ir(ir, @context) ==
               "Type.bitstring([Type.bitstringSegment(Type.integer(1n), {}), Type.bitstringSegment(Type.integer(2n), {})])"
    end
  end

  describe "bitstring segment" do
    test "no modifiers specified" do
      # <<123>>
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: []
      }

      assert encode_ir(ir) == "Type.bitstringSegment(Type.integer(123n), {})"
    end

    test "all modifiers specified" do
      # <<123::integer-size(16)-unit(1)-signed-big>>
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

      assert encode_ir(ir) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {type: "integer", size: Type.integer(16n), unit: 1n, signedness: "signed", endianness: "big"})/
    end

    test "single modifier specified" do
      # <<123::big>>
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [endianness: :big]
      }

      assert encode_ir(ir) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {endianness: "big"})/
    end

    test "from string type" do
      # <<"abc">>
      ir = %IR.BitstringSegment{value: %IR.StringType{value: "abc"}, modifiers: [type: "utf8"]}

      assert encode_ir(ir) ==
               ~s/Type.bitstringSegment(Type.string(\"abc\"), {type: "utf8"})/
    end

    test "from non-string type" do
      # <<123::big>>
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [endianness: :big]
      }

      assert encode_ir(ir) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {endianness: "big"})/
    end
  end

  describe "block" do
    test "empty" do
      # do
      # end
      ir = %IR.Block{expressions: []}

      assert encode_ir(ir) ==
               """
               ((context) => {
               return Type.atom("nil");
               })(context)\
               """
    end

    test "single expression" do
      # do
      #   1
      # end
      ir = %IR.Block{
        expressions: [
          %IR.IntegerType{value: 1}
        ]
      }

      assert encode_ir(ir) ==
               """
               ((context) => {
               return Type.integer(1n);
               })(context)\
               """
    end

    test "multiple expressions" do
      # do
      #   1
      #   2
      # end
      ir = %IR.Block{
        expressions: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }

      assert encode_ir(ir) ==
               """
               ((context) => {
               Type.integer(1n);
               return Type.integer(2n);
               })(context)\
               """
    end

    test "the last expression in the block, having a nested match operator" do
      # x + (y = 123)
      ir = %IR.Block{
        expressions: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :+,
            args: [
              %IR.Variable{name: :x},
              %IR.MatchOperator{left: %IR.Variable{name: :y}, right: %IR.IntegerType{value: 123}}
            ]
          }
        ]
      }

      assert encode_ir(ir) == """
             ((context) => {
             globalThis.hologram.return = Erlang["+/2"](context.vars.x, Interpreter.matchOperator(Type.integer(123n), Type.variablePattern("y"), context));
             Interpreter.updateVarsToMatchedValues(context);
             return globalThis.hologram.return;
             })(context)\
             """
    end

    test "the last expression in the block, not having a nested match operator" do
      # x + y
      ir = %IR.Block{
        expressions: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :+,
            args: [
              %IR.Variable{name: :x},
              %IR.Variable{name: :y}
            ]
          }
        ]
      }

      assert encode_ir(ir) == """
             ((context) => {
             return Erlang["+/2"](context.vars.x, context.vars.y);
             })(context)\
             """
    end

    test "not the last expression in the block, having a nested match operator" do
      # x + (y = 123)
      # :ok
      ir = %IR.Block{
        expressions: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :+,
            args: [
              %IR.Variable{name: :x},
              %IR.MatchOperator{left: %IR.Variable{name: :y}, right: %IR.IntegerType{value: 123}}
            ]
          },
          %IR.AtomType{value: :ok}
        ]
      }

      assert encode_ir(ir) == """
             ((context) => {
             Erlang["+/2"](context.vars.x, Interpreter.matchOperator(Type.integer(123n), Type.variablePattern("y"), context));
             Interpreter.updateVarsToMatchedValues(context);
             return Type.atom("ok");
             })(context)\
             """
    end

    test "not the last expression in the block, not having a nested match operator" do
      # x + y
      # :ok
      ir = %IR.Block{
        expressions: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :+,
            args: [
              %IR.Variable{name: :x},
              %IR.Variable{name: :y}
            ]
          },
          %IR.AtomType{value: :ok}
        ]
      }

      assert encode_ir(ir) == """
             ((context) => {
             Erlang["+/2"](context.vars.x, context.vars.y);
             return Type.atom("ok");
             })(context)\
             """
    end

    test "as a function argument" do
      # my_fun(1, (x = 2; x + 3))
      ir = %IR.LocalFunctionCall{
        function: :my_fun,
        args: [
          %IR.IntegerType{value: 1},
          %IR.Block{
            expressions: [
              %IR.MatchOperator{
                left: %IR.Variable{name: :x},
                right: %IR.IntegerType{value: 2}
              },
              %IR.RemoteFunctionCall{
                module: %IR.AtomType{value: :erlang},
                function: :+,
                args: [
                  %IR.Variable{name: :x},
                  %IR.IntegerType{value: 3}
                ]
              }
            ]
          }
        ]
      }

      assert encode_ir(ir) == """
             Erlang_["my_fun/2"](Type.integer(1n), ((context) => {
             Interpreter.matchOperator(Type.integer(2n), Type.variablePattern("x"), context);
             Interpreter.updateVarsToMatchedValues(context);
             return Erlang["+/2"](context.vars.x, Type.integer(3n));
             })(context))\
             """
    end
  end

  describe "case" do
    test "single-expression condition" do
      # case my_var do
      #   x when x == 100 -> :ok
      #   y -> y
      # end
      #
      # case my_var do
      #   x when :erlang.==(x, 100) -> :ok
      #   y -> y
      # end
      ir = %IR.Case{
        condition: %IR.Variable{name: :my_var},
        clauses: [
          %IR.Clause{
            match: %IR.Variable{name: :x},
            guards: [
              %IR.RemoteFunctionCall{
                module: %IR.AtomType{value: :erlang},
                function: :==,
                args: [
                  %IR.Variable{name: :x},
                  %IR.IntegerType{value: 100}
                ]
              }
            ],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :ok}]
            }
          },
          %IR.Clause{
            match: %IR.Variable{name: :y},
            guards: [],
            body: %IR.Block{
              expressions: [%IR.Variable{name: :y}]
            }
          }
        ]
      }

      assert encode_ir(ir) == """
             Interpreter.case(context.vars.my_var, [{match: Type.variablePattern("x"), guards: [(context) => Erlang["==/2"](context.vars.x, Type.integer(100n))], body: (context) => {
             return Type.atom("ok");
             }}, {match: Type.variablePattern("y"), guards: [], body: (context) => {
             return context.vars.y;
             }}], context)\
             """
    end

    test "multiple-expression condition" do
      # case (1; 2) do
      #   2 -> :ok
      # end
      ir = %IR.Case{
        condition: %IR.Block{
          expressions: [
            %IR.IntegerType{value: 1},
            %IR.IntegerType{value: 2}
          ]
        },
        clauses: [
          %IR.Clause{
            match: %IR.IntegerType{value: 2},
            guards: [],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :ok}]
            }
          }
        ]
      }

      assert encode_ir(ir) == """
             Interpreter.case((context) => {
             Type.integer(1n);
             return Type.integer(2n);
             }, [{match: Type.integer(2n), guards: [], body: (context) => {
             return Type.atom("ok");
             }}], context)\
             """
    end
  end

  describe "clause" do
    test "no guards" do
      # case 1 do
      #   x -> 1
      # end
      ir = %IR.Clause{
        match: %IR.Variable{name: :x},
        guards: [],
        body: %IR.Block{
          expressions: [%IR.IntegerType{value: 1}]
        }
      }

      assert encode_ir(ir) ==
               "{match: Type.variablePattern(\"x\"), guards: [], body: (context) => {\nreturn Type.integer(1n);\n}}"
    end

    test "single guard" do
      # case 1 do
      #   x when y -> 1
      # end
      ir = %IR.Clause{
        match: %IR.Variable{name: :x},
        guards: [%IR.Variable{name: :y}],
        body: %IR.Block{
          expressions: [%IR.IntegerType{value: 1}]
        }
      }

      assert encode_ir(ir) ==
               "{match: Type.variablePattern(\"x\"), guards: [(context) => context.vars.y], body: (context) => {\nreturn Type.integer(1n);\n}}"
    end

    test "multiple guards" do
      # case 1 do
      #   x when y when z -> 1
      # end
      ir = %IR.Clause{
        match: %IR.Variable{name: :x},
        guards: [%IR.Variable{name: :y}, %IR.Variable{name: :z}],
        body: %IR.Block{
          expressions: [%IR.IntegerType{value: 1}]
        }
      }

      assert encode_ir(ir) ==
               "{match: Type.variablePattern(\"x\"), guards: [(context) => context.vars.y, (context) => context.vars.z], body: (context) => {\nreturn Type.integer(1n);\n}}"
    end
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
        %IR.Clause{
          match: %IR.Variable{name: :x},
          guards: [
            %IR.RemoteFunctionCall{
              module: %IR.AtomType{value: :erlang},
              function: :<,
              args: [
                %IR.Variable{name: :x},
                %IR.IntegerType{value: 3}
              ]
            }
          ],
          body: %IR.ListType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.IntegerType{value: 2}
            ]
          }
        },
        %IR.Clause{
          match: %IR.Variable{name: :y},
          guards: [
            %IR.RemoteFunctionCall{
              module: %IR.AtomType{value: :erlang},
              function: :<,
              args: [
                %IR.Variable{name: :y},
                %IR.IntegerType{value: 5}
              ]
            }
          ],
          body: %IR.ListType{
            data: [
              %IR.IntegerType{value: 3},
              %IR.IntegerType{value: 4}
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

    assert encode_ir(ir) ==
             "Interpreter.comprehension([{match: Type.variablePattern(\"x\"), guards: [(context) => Erlang[\"</2\"](context.vars.x, Type.integer(3n))], body: (context) => Type.list([Type.integer(1n), Type.integer(2n)])}, {match: Type.variablePattern(\"y\"), guards: [(context) => Erlang[\"</2\"](context.vars.y, Type.integer(5n))], body: (context) => Type.list([Type.integer(3n), Type.integer(4n)])}], [(context) => Erlang[\"is_integer/1\"](context.vars.x), (context) => Erlang[\"is_integer/1\"](context.vars.y)], Type.map([]), true, (context) => Type.tuple([context.vars.x, context.vars.y]), context)"
  end

  test "comprehension filter" do
    # my_filter(a)
    ir = %IR.ComprehensionFilter{
      expression: %IR.LocalFunctionCall{
        function: :my_filter,
        args: [%IR.Variable{name: :a}]
      }
    }

    assert encode_ir(ir, %Context{module: MyModule}) ==
             "(context) => Elixir_MyModule[\"my_filter/1\"](context.vars.a)"
  end

  test "comprehension generator" do
    # {a, b} when my_guard(a, 2) -> [1, 2]
    ir = %IR.Clause{
      match: %IR.TupleType{
        data: [
          %IR.Variable{name: :a},
          %IR.Variable{name: :b}
        ]
      },
      guards: [
        %IR.LocalFunctionCall{
          function: :my_guard,
          args: [
            %IR.Variable{name: :a},
            %IR.IntegerType{value: 2}
          ]
        }
      ],
      body: %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }
    }

    assert encode_ir(ir, %Context{module: MyModule}) ==
             "{match: Type.tuple([Type.variablePattern(\"a\"), Type.variablePattern(\"b\")]), guards: [(context) => Elixir_MyModule[\"my_guard/2\"](context.vars.a, Type.integer(2n))], body: (context) => Type.list([Type.integer(1n), Type.integer(2n)])}"
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

    # cond do
    #   :erlang.<(x, 1) -> 1
    #   :erlang.<(x, 2) -> 2
    # end
    ir = %IR.Cond{clauses: [clause_1, clause_2]}

    assert encode_ir(ir) == """
           Interpreter.cond([{condition: (context) => Erlang["</2"](context.vars.x, Type.integer(1n)), body: (context) => {
           return Type.integer(1n);
           }}, {condition: (context) => Erlang["</2"](context.vars.x, Type.integer(2n)), body: (context) => {
           return Type.integer(2n);
           }}], context)\
           """
  end

  test "cond clause" do
    # :erlang.<(x, 3) ->
    #   1
    #   2
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

    assert encode_ir(ir) == """
           {condition: (context) => Erlang[\"</2\"](context.vars.x, Type.integer(3n)), body: (context) => {
           Type.integer(1n);
           return Type.integer(2n);
           }}\
           """
  end

  describe "cons operator" do
    # [1 | [2, 3]]
    @cons_operator_ir %IR.ConsOperator{
      head: %IR.IntegerType{value: 1},
      tail: %IR.ListType{data: [%IR.IntegerType{value: 2}, %IR.IntegerType{value: 3}]}
    }

    test "not inside pattern" do
      assert encode_ir(@cons_operator_ir, %Context{pattern?: false}) ==
               "Interpreter.consOperator(Type.integer(1n), Type.list([Type.integer(2n), Type.integer(3n)]))"
    end

    test "inside pattern" do
      assert encode_ir(@cons_operator_ir, %Context{pattern?: true}) ==
               "Type.consPattern(Type.integer(1n), Type.list([Type.integer(2n), Type.integer(3n)]))"
    end
  end

  test "dot operator" do
    # my_module.my_key
    ir = %IR.DotOperator{
      left: %IR.Variable{name: :my_module},
      right: %IR.AtomType{value: :my_key}
    }

    assert encode_ir(ir) ==
             "Interpreter.dotOperator(context.vars.my_module, Type.atom(\"my_key\"))"
  end

  test "encode_elixir_function/6" do
    clauses = [
      %IR.FunctionClause{
        params: [%IR.IntegerType{value: 9}],
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :expr_2}]
        }
      },
      %IR.FunctionClause{
        params: [%IR.Variable{name: :z}],
        guards: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :is_float,
            args: [%IR.Variable{name: :z}]
          }
        ],
        body: %IR.Block{
          expressions: [%IR.Variable{name: :z}]
        }
      }
    ]

    assert encode_elixir_function("Aaa.Bbb", :fun_2, 1, :private, clauses, %Context{}) == """
           Interpreter.defineElixirFunction("Aaa.Bbb", "fun_2", 1, "private", [{params: (context) => [Type.integer(9n)], guards: [], body: (context) => {
           return Type.atom("expr_2");
           }}, {params: (context) => [Type.variablePattern("z")], guards: [(context) => Erlang["is_float/1"](context.vars.z)], body: (context) => {
           return context.vars.z;
           }}]);\
           """
  end

  describe "encode_erlang_function/4" do
    test ":erlang module function that is implemented" do
      output = encode_erlang_function(:erlang, :+, 2, @erlang_source_dir)

      assert output == """
             Interpreter.defineErlangFunction("erlang", "+", 2, (left, right) => {
                 if (!Type.isNumber(left) || !Type.isNumber(right)) {
                   const blame = `${Interpreter.inspect(left)} + ${Interpreter.inspect(right)}`;
                   Interpreter.raiseArithmeticError(blame);
                 }

                 const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
                   left,
                   right,
                 );

                 const result = leftValue.value + rightValue.value;

                 return type === "float" ? Type.float(result) : Type.integer(result);
               });\
             """
    end

    test ":erlang module function that is not implemented" do
      output = encode_erlang_function(:erlang, :not_implemented, 2, @erlang_source_dir)

      assert output ==
               ~s/Interpreter.defineNotImplementedErlangFunction("erlang", "not_implemented", 2);/
    end

    test ":maps module function that is implemented" do
      output = encode_erlang_function(:maps, :get, 2, @erlang_source_dir)

      assert output == """
             Interpreter.defineErlangFunction("maps", "get", 2, (key, map) => {
                 const value = Erlang_Maps["get/3"](key, map, null);

                 if (value !== null) {
                   return value;
                 }

                 Interpreter.raiseKeyError(Interpreter.buildKeyErrorMsg(key, map));
               });\
             """
    end

    test ":maps module function that is not implemented" do
      output = encode_erlang_function(:maps, :not_implemented, 2, @erlang_source_dir)

      assert output ==
               ~s/Interpreter.defineNotImplementedErlangFunction("maps", "not_implemented", 2);/
    end
  end

  test "float type" do
    # 1.23
    assert encode_ir(%IR.FloatType{value: 1.23}) == "Type.float(1.23)"
  end

  describe "function clause" do
    # (x, y) do
    #  :expr_1
    #  :expr_2
    test "without guard" do
      ir = %IR.FunctionClause{
        params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
        }
      }

      assert encode_ir(ir) == """
             {params: (context) => [Type.variablePattern("x"), Type.variablePattern("y")], guards: [], body: (context) => {
             Type.atom("expr_1");
             return Type.atom("expr_2");
             }}\
             """
    end

    test "with single guard" do
      # (x, y) when :erlang.is_integer(x) do
      #  :expr_1
      #  :expr_2
      ir = %IR.FunctionClause{
        params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
        guards: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :is_integer,
            args: [%IR.Variable{name: :x}]
          }
        ],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
        }
      }

      assert encode_ir(ir) == """
             {params: (context) => [Type.variablePattern("x"), Type.variablePattern("y")], guards: [(context) => Erlang["is_integer/1"](context.vars.x)], body: (context) => {
             Type.atom("expr_1");
             return Type.atom("expr_2");
             }}\
             """
    end

    test "with multiple guards" do
      # (x, y) when :erlang.is_integer(x) when :erlang.is_integer(y) do
      #  :expr_1
      #  :expr_2
      ir = %IR.FunctionClause{
        params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
        guards: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :is_integer,
            args: [%IR.Variable{name: :x}]
          },
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: :erlang},
            function: :is_integer,
            args: [%IR.Variable{name: :y}]
          }
        ],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :expr_1}, %IR.AtomType{value: :expr_2}]
        }
      }

      assert encode_ir(ir) == """
             {params: (context) => [Type.variablePattern("x"), Type.variablePattern("y")], guards: [(context) => Erlang["is_integer/1"](context.vars.x), (context) => Erlang["is_integer/1"](context.vars.y)], body: (context) => {
             Type.atom("expr_1");
             return Type.atom("expr_2");
             }}\
             """
    end

    test "with match operator in param" do
      # (x = 1 = y) do
      #  :ok
      ir = %IR.FunctionClause{
        params: [
          %IR.MatchOperator{
            left: %IR.Variable{name: :x},
            right: %IR.MatchOperator{
              left: %IR.IntegerType{value: 1},
              right: %IR.Variable{name: :y}
            }
          }
        ],
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :ok}]
        }
      }

      assert encode_ir(ir) == """
             {params: (context) => [Interpreter.matchOperator(Interpreter.matchOperator(Type.variablePattern("y"), Type.integer(1n), context), Type.variablePattern("x"), context)], guards: [], body: (context) => {
             return Type.atom("ok");
             }}\
             """
    end
  end

  test "integer type" do
    # 123
    assert encode_ir(%IR.IntegerType{value: 123}) == "Type.integer(123n)"
  end

  describe "list type" do
    test "empty" do
      # []
      assert encode_ir(%IR.ListType{data: []}) == "Type.list([])"
    end

    test "non-empty" do
      # [1, :abc]
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode_ir(ir) == ~s/Type.list([Type.integer(1n), Type.atom("abc")])/
    end
  end

  test "local function call" do
    # my_fun!(1, 2)
    ir = %IR.LocalFunctionCall{
      function: :my_fun!,
      args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    }

    assert encode_ir(ir, %Context{module: Aaa.Bbb.Ccc}) ==
             "Elixir_Aaa_Bbb_Ccc[\"my_fun!/2\"](Type.integer(1n), Type.integer(2n))"
  end

  describe "map type" do
    test "empty" do
      # %{}
      assert encode_ir(%IR.MapType{data: []}) == "Type.map([])"
    end

    test "single key" do
      # %{a: 1}
      ir = %IR.MapType{
        data: [
          {
            %IR.AtomType{value: :a},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode_ir(ir) == ~s/Type.map([[Type.atom("a"), Type.integer(1n)]])/
    end

    test "multiple keys" do
      # %{a: 1, b: 2}
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert encode_ir(ir) ==
               ~s/Type.map([[Type.atom("a"), Type.integer(1n)], [Type.atom("b"), Type.integer(2n)]])/
    end

    test "keys are sorted" do
      # %{x: 9, b: 1, a: 2, y: 8}
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :x}, %IR.IntegerType{value: 9}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 2}},
          {%IR.AtomType{value: :y}, %IR.IntegerType{value: 8}}
        ]
      }

      assert encode_ir(ir) ==
               ~s/Type.map([[Type.atom("a"), Type.integer(2n)], [Type.atom("b"), Type.integer(1n)], [Type.atom("x"), Type.integer(9n)], [Type.atom("y"), Type.integer(8n)]])/
    end
  end

  describe "match operator" do
    test "literal value on both sides" do
      # 1 = 2
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.IntegerType{value: 2}
      }

      assert encode_ir(ir) ==
               "Interpreter.matchOperator(Type.integer(2n), Type.integer(1n), context)"
    end

    test "variable in pattern" do
      # x = 2
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.IntegerType{value: 2}
      }

      assert encode_ir(ir) ==
               ~s/Interpreter.matchOperator(Type.integer(2n), Type.variablePattern("x"), context)/
    end

    test "variable in expression" do
      # 1 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.Variable{name: :x}
      }

      assert encode_ir(ir) ==
               "Interpreter.matchOperator(context.vars.x, Type.integer(1n), context)"
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

      assert encode_ir(ir) ==
               ~s/Interpreter.matchOperator(Interpreter.matchOperator(Type.integer(3n), Type.integer(2n), context), Type.variablePattern("x"), context)/
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

      assert encode_ir(ir) ==
               ~s/Interpreter.matchOperator(Interpreter.matchOperator(Type.integer(3n), Type.variablePattern("x"), context), Type.integer(1n), context)/
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

      assert encode_ir(ir) ==
               "Interpreter.matchOperator(Interpreter.matchOperator(context.vars.x, Type.integer(2n), context), Type.integer(1n), context)"
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

      assert encode_ir(ir) ==
               ~s/Interpreter.matchOperator(Interpreter.matchOperator(Type.tuple([Type.integer(1n), Type.integer(2n), Interpreter.matchOperator(context.vars.f, Type.variablePattern("e"), context)]), Type.tuple([Type.integer(1n), Interpreter.matchOperator(Type.variablePattern("d"), Type.variablePattern("c"), context), Type.integer(3n)]), context), Type.tuple([Interpreter.matchOperator(Type.variablePattern("b"), Type.variablePattern("a"), context), Type.integer(2n), Type.integer(3n)]), context)/
    end
  end

  test "match placeholder" do
    # _abc
    assert encode_ir(%IR.MatchPlaceholder{}) == "Type.matchPlaceholder()"
  end

  describe "module attribute operator" do
    test "without special characters" do
      # @abc
      assert encode_ir(%IR.ModuleAttributeOperator{name: :abc}) == ~s'context.vars["@abc"]'
    end

    test "with special characters" do
      # @abc?
      assert encode_ir(%IR.ModuleAttributeOperator{name: :abc?}) == ~s'context.vars["@abc?"]'
    end
  end

  describe "module definition" do
    test "valid IR" do
      # defmodule Aaa.Bbb do
      #   def fun_1(9, 8), :expr_1

      #   def fun_1(c) when :erlang.is_integer(c), do: c

      #   def fun_1(a, b) do
      #     :erlang.+(a, b)
      #   end

      #   defp fun_2(x, y) do
      #     :erlang.*(x, y)
      #   end

      #   defp fun_2(9), do: :expr_2

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
                  %IR.IntegerType{value: 9},
                  %IR.IntegerType{value: 8}
                ],
                guards: [],
                body: %IR.Block{
                  expressions: [%IR.AtomType{value: :expr_1}]
                }
              }
            },
            %IR.FunctionDefinition{
              name: :fun_1,
              arity: 1,
              visibility: :public,
              clause: %IR.FunctionClause{
                params: [%IR.Variable{name: :c}],
                guards: [
                  %IR.RemoteFunctionCall{
                    module: %IR.AtomType{value: :erlang},
                    function: :is_integer,
                    args: [%IR.Variable{name: :c}]
                  }
                ],
                body: %IR.Block{
                  expressions: [%IR.Variable{name: :c}]
                }
              }
            },
            %IR.FunctionDefinition{
              name: :fun_1,
              arity: 2,
              visibility: :public,
              clause: %IR.FunctionClause{
                params: [
                  %IR.Variable{name: :a},
                  %IR.Variable{name: :b}
                ],
                guards: [],
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
              name: :fun_2,
              arity: 2,
              visibility: :private,
              clause: %IR.FunctionClause{
                params: [
                  %IR.Variable{name: :x},
                  %IR.Variable{name: :y}
                ],
                guards: [],
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
                params: [%IR.IntegerType{value: 9}],
                guards: [],
                body: %IR.Block{
                  expressions: [%IR.AtomType{value: :expr_2}]
                }
              }
            },
            %IR.FunctionDefinition{
              name: :fun_2,
              arity: 1,
              visibility: :private,
              clause: %IR.FunctionClause{
                params: [%IR.Variable{name: :z}],
                guards: [
                  %IR.RemoteFunctionCall{
                    module: %IR.AtomType{value: :erlang},
                    function: :is_float,
                    args: [%IR.Variable{name: :z}]
                  }
                ],
                body: %IR.Block{
                  expressions: [%IR.Variable{name: :z}]
                }
              }
            }
          ]
        }
      }

      assert encode_ir(ir) == """
             Interpreter.defineElixirFunction("Aaa.Bbb", "fun_1", 1, "public", [{params: (context) => [Type.variablePattern("c")], guards: [(context) => Erlang["is_integer/1"](context.vars.c)], body: (context) => {
             return context.vars.c;
             }}]);

             Interpreter.defineElixirFunction("Aaa.Bbb", "fun_1", 2, "public", [{params: (context) => [Type.integer(9n), Type.integer(8n)], guards: [], body: (context) => {
             return Type.atom("expr_1");
             }}, {params: (context) => [Type.variablePattern("a"), Type.variablePattern("b")], guards: [], body: (context) => {
             return Erlang["+/2"](context.vars.a, context.vars.b);
             }}]);

             Interpreter.defineElixirFunction("Aaa.Bbb", "fun_2", 1, "private", [{params: (context) => [Type.integer(9n)], guards: [], body: (context) => {
             return Type.atom("expr_2");
             }}, {params: (context) => [Type.variablePattern("z")], guards: [(context) => Erlang["is_float/1"](context.vars.z)], body: (context) => {
             return context.vars.z;
             }}]);

             Interpreter.defineElixirFunction("Aaa.Bbb", "fun_2", 2, "private", [{params: (context) => [Type.variablePattern("x"), Type.variablePattern("y")], guards: [], body: (context) => {
             return Erlang["*/2"](context.vars.x, context.vars.y);
             }}]);\
             """
    end

    test "invalid IR" do
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
                  %IR.IntegerType{value: 9},
                  %IR.IntegerType{value: 8}
                ],
                guards: [],
                body: %IR.Block{
                  expressions: [
                    %IR.RemoteFunctionCall{
                      module: %IR.AtomType{value: :erlang},
                      function: :apply,
                      args: [
                        %IR.AtomType{value: MyModule},
                        # intentional error (it should be %IR.AtomType{value: :my_fun} or %IR.Variable{name: :my_fun})
                        :my_fun,
                        %IR.ListType{data: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]}
                      ]
                    }
                  ]
                }
              }
            }
          ]
        }
      }

      expected_msg = """
      can't encode Aaa.Bbb module definition
      no function clause matching in Hologram.Compiler.Encoder.encode_ir/2\
      """

      assert_raise RuntimeError, expected_msg, fn -> encode_ir(ir) end
    end
  end

  test "pid" do
    # #PID<0.11.222>
    ir = %IR.PIDType{value: pid("0.11.222")}

    assert encode_ir(ir) == ~s/Type.pid("nonode@nohost", [0, 11, 222])/
  end

  test "pin operator" do
    # ^abc
    assert encode_ir(%IR.PinOperator{variable: %IR.Variable{name: :abc, version: 2}}) ==
             "context.vars.abc_2"
  end

  test "port" do
    # #Port<0.11>
    ir = %IR.PortType{value: port("0.11")}

    assert encode_ir(ir) == ~s/Type.port("0.11")/
  end

  test "reference" do
    # #Reference<0.1.2.3>
    ir = %IR.ReferenceType{value: ref("0.1.2.3")}

    assert encode_ir(ir) == ~s/Type.reference("0.1.2.3")/
  end

  describe "remote function call" do
    test "called on a module alias" do
      # Aaa.Bbb.Ccc.my_fun!(1, 2)
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Aaa.Bbb.Ccc},
        function: :my_fun!,
        args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
      }

      assert encode_ir(ir) ==
               "Elixir_Aaa_Bbb_Ccc[\"my_fun!/2\"](Type.integer(1n), Type.integer(2n))"
    end

    test "called on variable" do
      # x.my_fun!(1, 2)
      ir = %IR.RemoteFunctionCall{
        module: %IR.Variable{name: :x},
        function: :my_fun!,
        args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
      }

      assert encode_ir(ir) ==
               ~s'Interpreter.callNamedFunction(context.vars.x, Type.atom("my_fun!"), Type.list([Type.integer(1n), Type.integer(2n)]), context)'
    end

    test "called on expression" do
      # (case my_var do
      #   :a -> MyModule1
      #   :b -> MyModule2
      # end).my_fun!(1, 2)
      ir = %IR.RemoteFunctionCall{
        module: %IR.Case{
          condition: %IR.Variable{name: :my_var},
          clauses: [
            %IR.Clause{
              match: %IR.AtomType{value: :a},
              guards: [],
              body: %IR.Block{
                expressions: [%IR.AtomType{value: MyModule1}]
              }
            },
            %IR.Clause{
              match: %IR.AtomType{value: :b},
              guards: [],
              body: %IR.Block{
                expressions: [%IR.AtomType{value: MyModule2}]
              }
            }
          ]
        },
        function: :my_fun!,
        args: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }

      assert encode_ir(ir, %Context{module: MyModule}) == """
             Interpreter.callNamedFunction(Interpreter.case(context.vars.my_var, [{match: Type.atom("a"), guards: [], body: (context) => {
             return Type.atom("Elixir.MyModule1");
             }}, {match: Type.atom("b"), guards: [], body: (context) => {
             return Type.atom("Elixir.MyModule2");
             }}], context), Type.atom("my_fun!"), Type.list([Type.integer(1n), Type.integer(2n)]), context)\
             """
    end

    test ":erlang.andalso/2 call" do
      # :erlang.andalso(1, 2)
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :andalso,
        args: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }

      assert encode_ir(ir) ==
               ~s'Erlang["andalso/2"]((context) => Type.integer(1n), (context) => Type.integer(2n), context)'
    end

    test ":erlang.apply/3 call with non-variable args" do
      # :erlang.apply(MyModule, :my_fun, [1, 2])
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.AtomType{value: MyModule},
          %IR.AtomType{value: :my_fun},
          %IR.ListType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.IntegerType{value: 2}
            ]
          }
        ]
      }

      assert encode_ir(ir) ==
               ~s'Interpreter.callNamedFunction(Type.atom("Elixir.MyModule"), Type.atom("my_fun"), Type.list([Type.integer(1n), Type.integer(2n)]), context)'
    end

    test ":erlang.apply/3 call with variable args" do
      # :erlang.apply(module, fun, args)
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.Variable{name: :module},
          %IR.Variable{name: :fun},
          %IR.Variable{name: :args}
        ]
      }

      assert encode_ir(ir) ==
               "Interpreter.callNamedFunction(context.vars.module, context.vars.fun, context.vars.args, context)"
    end

    test ":erlang.orelse/2 call" do
      # :erlang.orelse(1, 2)
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :orelse,
        args: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }

      assert encode_ir(ir) ==
               ~s'Erlang["orelse/2"]((context) => Type.integer(1n), (context) => Type.integer(2n), context)'
    end
  end

  describe "string type" do
    test "printable ASCII char" do
      # "a"
      ir = %IR.StringType{value: "a"}

      assert encode_ir(ir) == ~s/Type.bitstring("a")/
    end

    test "printable Unicode char" do
      # "全"
      ir = %IR.StringType{value: "全"}

      assert encode_ir(ir) == ~s/Type.bitstring("全")/
    end

    test "multiple printable chars" do
      # "abc全息图"
      ir = %IR.StringType{value: "abc全息图"}

      assert encode_ir(ir) == ~s/Type.bitstring("abc全息图")/
    end

    test "backslash char" do
      # "\\"
      ir = %IR.StringType{value: "\\"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\\\")/
    end

    test "double quote char" do
      # "\""
      ir = %IR.StringType{value: "\""}

      assert encode_ir(ir) == ~s/Type.bitstring("\\\"")/
    end

    test "beep (special) char" do
      # "\a"
      ir = %IR.StringType{value: "\a"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\x07")/
    end

    test "backspace (non-printable) char" do
      # "\b"
      ir = %IR.StringType{value: "\b"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\b")/
    end

    test "form feed (non-printable) char" do
      # "\f"
      ir = %IR.StringType{value: "\f"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\f")/
    end

    test "line feed (non-printable) char" do
      # "\n"
      ir = %IR.StringType{value: "\n"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\n")/
    end

    test "carriage return (non-printable) char" do
      # "\r"
      ir = %IR.StringType{value: "\r"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\r")/
    end

    test "horizontal tab (non-printable) char" do
      # "\t"
      ir = %IR.StringType{value: "\t"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\t")/
    end

    test "vertical tab (non-printable) char" do
      # "\v"
      ir = %IR.StringType{value: "\v"}

      assert encode_ir(ir) == ~s/Type.bitstring("\\v")/
    end

    test "line seperator char" do
      # <<8_232::utf8>>
      ir = %IR.StringType{value: <<8_232::utf8>>}

      assert encode_ir(ir) == ~s/Type.bitstring("\\u{2028}")/
    end

    test "paragraph seperator char" do
      # <<8_233::utf8>>
      ir = %IR.StringType{value: <<8_233::utf8>>}

      assert encode_ir(ir) == ~s/Type.bitstring("\\u{2029}")/
    end

    test "non-printable Unicode char" do
      # <<133::utf8>> (equivalent to <<194, 133>>)
      ir = %IR.StringType{value: <<133::utf8>>}

      assert encode_ir(ir) == ~s/Type.bitstring("\\u{85}")/
    end

    test "multiple non-printable Unicode chars" do
      # <<133::utf8, 134::utf8, 135::utf8>>
      # equivalent to: <<194, 133, 194, 134, 194, 135>>
      ir = %IR.StringType{value: <<133::utf8, 134::utf8, 135::utf8>>}

      assert encode_ir(ir) == ~s/Type.bitstring("\\u{85}\\u{86}\\u{87}")/
    end

    test "single-byte char outside of the standard ASCII range" do
      ir = %IR.StringType{value: <<240>>}

      assert encode_ir(ir) == ~s/Type.bitstring("\\xF0")/
    end

    test "multiple single-byte chars outside of the standard ASCII range" do
      ir = %IR.StringType{value: <<240, 145, 163>>}

      assert encode_ir(ir) == ~s/Type.bitstring("\\xF0\\x91\\xA3")/
    end

    test "multiple printable and non-printable chars" do
      # "abc\n全息图\t" <> <<133::utf8, 134::utf8, 135::utf8>>
      # equivalent to: <<97, 98, 99, 10, 229, 133, 168, 230, 129, 175, 229, 155, 190, 9, 194, 133, 194, 134, 194, 135>>

      ir = %IR.StringType{
        value:
          <<97, 98, 99, 10, 229, 133, 168, 230, 129, 175, 229, 155, 190, 9, 194, 133, 194, 134,
            194, 135>>
      }

      assert encode_ir(ir) == ~s/Type.bitstring("abc\\n全息图\\t\\u{85}\\u{86}\\u{87}")/
    end
  end

  describe "try" do
    test "body" do
      # try do
      #   :ok
      # end
      ir = %IR.Try{
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :ok}]
        },
        rescue_clauses: [],
        catch_clauses: [],
        else_clauses: [],
        after_block: nil
      }

      assert encode_ir(ir) == """
             Interpreter.try((context) => {
             return Type.atom("ok");
             }, [], [], [], null, context)\
             """
    end

    test "single rescue clause / without variable / with single module" do
      # try do
      #   :ok
      # rescue
      #   RuntimeError -> :error
      # end
      ir = %IR.Try{
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :ok}]
        },
        rescue_clauses: [
          %IR.TryRescueClause{
            variable: nil,
            modules: [%IR.AtomType{value: RuntimeError}],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :error}]
            }
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_block: nil
      }

      assert encode_ir(ir) == """
             Interpreter.try((context) => {
             return Type.atom("ok");
             }, [{variable: null, modules: [Type.atom("Elixir.RuntimeError")], body: (context) => {
             return Type.atom("error");
             }}], [], [], null, context)\
             """
    end

    test "multiple rescue clauses" do
      # try do
      #   :ok
      # rescue
      #   ArgumentError -> :error_1
      #   RuntimeError -> :error_2
      # end
      ir = %IR.Try{
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :ok}]
        },
        rescue_clauses: [
          %IR.TryRescueClause{
            variable: nil,
            modules: [%IR.AtomType{value: ArgumentError}],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :error_1}]
            }
          },
          %IR.TryRescueClause{
            variable: nil,
            modules: [%IR.AtomType{value: RuntimeError}],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :error_2}]
            }
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_block: nil
      }

      assert encode_ir(ir) == """
             Interpreter.try((context) => {
             return Type.atom("ok");
             }, [{variable: null, modules: [Type.atom("Elixir.ArgumentError")], body: (context) => {
             return Type.atom("error_1");
             }}, {variable: null, modules: [Type.atom("Elixir.RuntimeError")], body: (context) => {
             return Type.atom("error_2");
             }}], [], [], null, context)\
             """
    end

    test "with variable" do
      # try do
      #   :ok
      # rescue
      #   e -> :error
      # end
      ir = %IR.Try{
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :ok}]
        },
        rescue_clauses: [
          %IR.TryRescueClause{
            variable: %IR.Variable{name: :e},
            modules: [],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :error}]
            }
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_block: nil
      }

      assert encode_ir(ir) == """
             Interpreter.try((context) => {
             return Type.atom("ok");
             }, [{variable: Type.variablePattern("e"), modules: [], body: (context) => {
             return Type.atom("error");
             }}], [], [], null, context)\
             """
    end

    test "with multiple modules" do
      # try do
      #   :ok
      # rescue
      #   [ArgumentError, RuntimeError]-> :error
      # end
      ir = %IR.Try{
        body: %IR.Block{
          expressions: [%IR.AtomType{value: :ok}]
        },
        rescue_clauses: [
          %IR.TryRescueClause{
            variable: nil,
            modules: [
              %IR.AtomType{value: ArgumentError},
              %IR.AtomType{value: RuntimeError}
            ],
            body: %IR.Block{
              expressions: [%IR.AtomType{value: :error}]
            }
          }
        ],
        catch_clauses: [],
        else_clauses: [],
        after_block: nil
      }

      assert encode_ir(ir) == """
             Interpreter.try((context) => {
             return Type.atom("ok");
             }, [{variable: null, modules: [Type.atom("Elixir.ArgumentError"), Type.atom("Elixir.RuntimeError")], body: (context) => {
             return Type.atom("error");
             }}], [], [], null, context)\
             """
    end
  end

  describe "tuple type" do
    test "empty" do
      # {}
      assert encode_ir(%IR.TupleType{data: []}) == "Type.tuple([])"
    end

    test "non-empty" do
      # {1, :abc}
      ir = %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode_ir(ir) == ~s/Type.tuple([Type.integer(1n), Type.atom("abc")])/
    end
  end

  describe "variable" do
    test "not inside pattern, without special characters, non-versioned" do
      # my_var
      assert encode_ir(%IR.Variable{name: :my_var, version: nil}, %Context{pattern?: false}) ==
               "context.vars.my_var"
    end

    test "not inside pattern, with special characters, non-versioned" do
      # my_var?
      assert encode_ir(%IR.Variable{name: :my_var?, version: nil}, %Context{pattern?: false}) ==
               ~s'context.vars["my_var?"]'
    end

    test "inside pattern, without special characters, non-versioned" do
      # my_var
      assert encode_ir(%IR.Variable{name: :my_var, version: nil}, %Context{pattern?: true}) ==
               ~s/Type.variablePattern("my_var")/
    end

    test "inside pattern, with special characters, non-versioned" do
      # my_var?
      assert encode_ir(%IR.Variable{name: :my_var?, version: nil}, %Context{pattern?: true}) ==
               ~s/Type.variablePattern("my_var?")/
    end

    test "not inside pattern, without special characters, versioned" do
      # my_var
      assert encode_ir(%IR.Variable{name: :my_var, version: 3}, %Context{pattern?: false}) ==
               "context.vars.my_var_3"
    end

    test "not inside pattern, with special characters, versioned" do
      # my_var?
      assert encode_ir(%IR.Variable{name: :my_var?, version: 3}, %Context{pattern?: false}) ==
               ~s'context.vars["my_var?_3"]'
    end

    test "inside pattern, without special characters, versioned" do
      # my_var
      assert encode_ir(%IR.Variable{name: :my_var, version: 3}, %Context{pattern?: true}) ==
               ~s/Type.variablePattern("my_var_3")/
    end

    test "inside pattern, with special characters, versioned" do
      # my_var?
      assert encode_ir(%IR.Variable{name: :my_var?, version: 3}, %Context{pattern?: true}) ==
               ~s/Type.variablePattern("my_var?_3")/
    end
  end

  # TODO: finish implementing
  test "with" do
    assert encode_ir(%IR.With{}) == "Interpreter.with()"
  end

  describe "encode_as_class_name/1" do
    test "Elixir module alias without camel case segments" do
      assert encode_as_class_name(Aaa.Bbb.Ccc) == "Elixir_Aaa_Bbb_Ccc"
    end

    test "Elixir module alias with camel case segments" do
      assert encode_as_class_name(AaaBbb.CccDdd) == "Elixir_AaaBbb_CccDdd"
    end

    test ":erlang alias" do
      assert encode_as_class_name(:erlang) == "Erlang"
    end

    test "single-segment Erlang module alias" do
      assert encode_as_class_name(:aaa) == "Erlang_Aaa"
    end

    test "multiple-segment Erlang module alias" do
      assert encode_as_class_name(:aaa_bbb) == "Erlang_Aaa_Bbb"
    end
  end

  describe "encode_term/1" do
    test "can be encoded into JavaScript" do
      assert encode_term(123) == {:ok, "Type.integer(123n)"}
    end

    test "can't be encoded into JavaScript" do
      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains an anonymous function that is not a named function capture"
        else
          "term contains an anonymous function that is not a remote function capture"
        end

      assert encode_term(fn x -> x end) == {:error, expected_msg}
    end
  end

  describe "encode_term!/1" do
    test "anonymous function (non-capture)" do
      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains an anonymous function that is not a named function capture"
        else
          "term contains an anonymous function that is not a remote function capture"
        end

      assert_error ArgumentError, expected_msg, fn -> encode_term!(fn x, y -> x * y end) end
    end

    test "anonymous function (capture)" do
      assert encode_term!(&DateTime.now/2) == """
             Type.functionCapture("DateTime", "now", 2, [{params: (context) => [Type.variablePattern("$1"), Type.variablePattern("$2")], guards: [], body: (context) => {
             return Elixir_DateTime["now/2"](context.vars["$1"], context.vars["$2"]);
             }}], context)\
             """
    end

    test "atom" do
      assert encode_term!(:abc) == ~s/Type.atom("abc")/
    end

    test "bistring" do
      assert encode_term!("abc") == ~s/Type.bitstring("abc")/
    end

    test "float, non-zero" do
      assert encode_term!(1.23) == "Type.float(1.23)"
    end

    test "float, signed zero, positive" do
      assert encode_term!(+0.0) == "Type.float(0.0)"
    end

    test "float, signed zero, negative" do
      assert encode_term!(-0.0) == "Type.float(-0.0)"
    end

    test "integer" do
      assert encode_term!(123) == "Type.integer(123n)"
    end

    test "list" do
      assert encode_term!([:abc, 123]) == ~s/Type.list([Type.atom("abc"), Type.integer(123n)])/
    end

    test "map" do
      assert encode_term!(%{:a => 1, "b" => 2.0}) ==
               ~s/Type.map([[Type.atom("a"), Type.integer(1n)], [Type.bitstring("b"), Type.float(2.0)]])/
    end

    test "pid" do
      assert encode_term!(pid("0.11.222")) == ~s/Type.pid("nonode@nohost", [0, 11, 222])/
    end

    test "port" do
      assert encode_term!(port("0.11")) == ~s/Type.port("0.11")/
    end

    test "reference" do
      assert encode_term!(ref("0.1.2.3")) == ~s/Type.reference("0.1.2.3")/
    end

    test "tuple" do
      assert encode_term!({:abc, 123}) == ~s/Type.tuple([Type.atom("abc"), Type.integer(123n)])/
    end
  end
end
