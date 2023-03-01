defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Expander

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Expander.Module1

  @context_dummy %Context{
    variables: MapSet.new([:__context_dummy__])
  }

  @context_with_aliases %Context{
    aliases: %{Seg1: [:Seg2, :Seg3]}
  }

  @context_with_module_attributes %Context{
    module_attributes: %{
      a: %IR.IntegerType{value: 1},
      c: %IR.IntegerType{value: 3}
    }
  }

  # --- OPERATORS ---

  test "addition operator" do
    ir = %IR.AdditionOperator{
      left: %IR.ModuleAttributeOperator{name: :a},
      right: %IR.ModuleAttributeOperator{name: :c}
    }

    assert expand(ir, @context_with_module_attributes) ==
             {%IR.AdditionOperator{
                left: %IR.IntegerType{value: 1},
                right: %IR.IntegerType{value: 3}
              }, @context_with_module_attributes}
  end

  test "equal to operator" do
    ir = %IR.EqualToOperator{
      left: %IR.ModuleAttributeOperator{name: :a},
      right: %IR.ModuleAttributeOperator{name: :c}
    }

    assert expand(ir, @context_with_module_attributes) ==
             {%IR.EqualToOperator{
                left: %IR.IntegerType{value: 1},
                right: %IR.IntegerType{value: 3}
              }, @context_with_module_attributes}
  end

  test "match operator" do
    ir = %IR.MatchOperator{
      bindings: [
        %IR.Binding{
          name: :x,
          access_path: [%IR.MatchAccess{}, %IR.MapAccess{key: %IR.Alias{segments: [:A]}}]
        },
        %IR.Binding{
          name: :y,
          access_path: [%IR.MatchAccess{}, %IR.MapAccess{key: %IR.Alias{segments: [:B]}}]
        }
      ],
      left: %IR.MapType{
        data: [
          {%IR.Alias{segments: [:A]}, %IR.Variable{name: :x}},
          {%IR.Alias{segments: [:B]}, %IR.Variable{name: :y}}
        ]
      },
      right: %IR.MapType{
        data: [
          {%IR.Alias{segments: [:A]}, %IR.IntegerType{value: 1}},
          {%IR.Alias{segments: [:B]}, %IR.IntegerType{value: 2}}
        ]
      }
    }

    context = %Context{variables: MapSet.new([:m, :n])}

    assert expand(ir, context) ==
             {%IR.MatchOperator{
                bindings: [
                  %IR.Binding{
                    name: :x,
                    access_path: [
                      %IR.MatchAccess{},
                      %IR.MapAccess{
                        key: %IR.ModuleType{module: A, segments: [:A]}
                      }
                    ]
                  },
                  %IR.Binding{
                    name: :y,
                    access_path: [
                      %IR.MatchAccess{},
                      %IR.MapAccess{
                        key: %IR.ModuleType{module: B, segments: [:B]}
                      }
                    ]
                  }
                ],
                left: %IR.MapType{
                  data: [
                    {%IR.ModuleType{module: A, segments: [:A]}, %IR.Variable{name: :x}},
                    {%IR.ModuleType{module: B, segments: [:B]}, %IR.Variable{name: :y}}
                  ]
                },
                right: %IR.MapType{
                  data: [
                    {%IR.ModuleType{module: A, segments: [:A]}, %IR.IntegerType{value: 1}},
                    {%IR.ModuleType{module: B, segments: [:B]}, %IR.IntegerType{value: 2}}
                  ]
                }
              }, %Context{variables: MapSet.new([:m, :n, :x, :y])}}
  end

  test "module attribute operator" do
    ir = %IR.ModuleAttributeOperator{name: :c}

    assert expand(ir, @context_with_module_attributes) ==
             {%IR.IntegerType{value: 3}, @context_with_module_attributes}
  end

  # --- DATA TYPES ---

  test "atom type" do
    ir = %IR.AtomType{value: :abc}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  test "boolean type" do
    ir = %IR.BooleanType{value: true}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  test "float type" do
    ir = %IR.FloatType{value: 1.23}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  test "integer type" do
    ir = %IR.IntegerType{value: 1}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  test "map" do
    ir = %IR.MapType{
      data: [
        {%IR.Alias{segments: [:A]}, %IR.Alias{segments: [:B]}},
        {%IR.Alias{segments: [:C]}, %IR.Alias{segments: [:D]}}
      ]
    }

    assert expand(ir, @context_dummy) ==
             {%IR.MapType{
                data: [
                  {%IR.ModuleType{module: A, segments: [:A]},
                   %IR.ModuleType{module: B, segments: [:B]}},
                  {%IR.ModuleType{module: C, segments: [:C]},
                   %IR.ModuleType{module: D, segments: [:D]}}
                ]
              }, @context_dummy}
  end

  test "module type" do
    ir = %IR.ModuleType{module: A.B, segments: [:A, :B]}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  test "nil type" do
    ir = %IR.NilType{}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  # --- PSEUDO-VARIABLES ---

  test "env pseudo-variable" do
    ir = %IR.EnvPseudoVariable{}

    assert {%IR.StructType{
              module: %IR.ModuleType{module: Macro.Env}
            }, @context_dummy} = expand(ir, @context_dummy)
  end

  test "module pseudo-variable" do
    ir = %IR.ModulePseudoVariable{}
    module = %IR.ModuleType{module: A.B, segments: [:A, :B]}
    context = %Context{module: module}

    assert expand(ir, context) == {module, context}
  end

  # --- DIRECTIVES ---

  describe "alias directive" do
    test "which doesn't use any other alias" do
      ir = %IR.AliasDirective{alias_segs: [:A, :B], as: :C}

      assert expand(ir, %Context{}) ==
               {%IR.IgnoredExpression{type: :alias_directive}, %Context{aliases: %{C: [:A, :B]}}}
    end

    test "which uses an alias defined before it" do
      ir = %IR.AliasDirective{alias_segs: [:C, :D], as: :E}
      context = %Context{aliases: %{C: [:A, :B]}}

      assert expand(ir, context) ==
               {%IR.IgnoredExpression{type: :alias_directive},
                %Context{aliases: %{C: [:A, :B], E: [:A, :B, :D]}}}
    end

    test "which uses an alias defined after it" do
      ir = %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
      context = %Context{aliases: %{E: [:C, :D]}}

      assert expand(ir, context) ==
               {%IR.IgnoredExpression{type: :alias_directive},
                %Context{aliases: %{C: [:A, :B], E: [:C, :D]}}}
    end
  end

  describe "import directive" do
    test "no opts" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: [],
        except: []
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{
               fun_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               fun_2: %{1 => Module1},
               fun_3: %{2 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{
               macro_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               macro_3: %{2 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "'only' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: [fun_2: 1, macro_3: 2],
        except: []
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{fun_2: %{1 => Module1}}
      assert context.macros == %{macro_3: %{2 => Module1}}
    end

    test "'except' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: [],
        except: [fun_2: 1, macro_3: 2]
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{
               fun_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               fun_3: %{2 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{
               macro_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only functions without 'except' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: :functions,
        except: []
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{
               fun_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               fun_2: %{1 => Module1},
               fun_3: %{2 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{}
    end

    test "only functions with 'except' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: :functions,
        except: [fun_1: 0, fun_3: 2]
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{
               fun_1: %{
                 1 => Module1,
                 2 => Module1
               },
               fun_2: %{1 => Module1},
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{}
    end

    test "only macros without 'except' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: :macros,
        except: []
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{}

      assert context.macros == %{
               macro_1: %{
                 0 => Module1,
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               macro_3: %{2 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only macros with 'except' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: :macros,
        except: [macro_1: 0, macro_3: 2]
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{}

      assert context.macros == %{
               macro_1: %{
                 1 => Module1,
                 2 => Module1
               },
               macro_2: %{1 => Module1},
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only sigils without 'except' opts" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: :sigils,
        except: []
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{
               sigil_a: %{2 => Module1},
               sigil_b: %{2 => Module1}
             }

      assert context.macros == %{
               sigil_c: %{2 => Module1},
               sigil_d: %{2 => Module1}
             }
    end

    test "only sigils with 'except' opts" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: :sigils,
        except: [sigil_b: 2, sigil_d: 2]
      }

      assert {%IR.IgnoredExpression{type: :import_directive}, %Context{} = context} =
               expand(ir, %Context{})

      assert context.functions == %{sigil_a: %{2 => Module1}}
      assert context.macros == %{sigil_c: %{2 => Module1}}
    end
  end

  # --- DEFINITIONS ---

  describe "module attribute definition" do
    test "expression doesn't use other module attributes and isn't a macro call" do
      ir = %IR.ModuleAttributeDefinition{
        name: :b,
        expression: %IR.AdditionOperator{
          left: %IR.IntegerType{value: 5},
          right: %IR.IntegerType{value: 6}
        }
      }

      assert expand(ir, @context_with_module_attributes) == {
               %IR.IgnoredExpression{type: :module_attribute_definition},
               %Context{
                 module_attributes: %{
                   a: %IR.IntegerType{value: 1},
                   b: %IR.IntegerType{value: 11},
                   c: %IR.IntegerType{value: 3}
                 }
               }
             }
    end

    test "expression uses other module attributes" do
      ir = %IR.ModuleAttributeDefinition{
        name: :b,
        expression: %IR.AdditionOperator{
          left: %IR.ModuleAttributeOperator{name: :a},
          right: %IR.ModuleAttributeOperator{name: :c}
        }
      }

      assert expand(ir, @context_with_module_attributes) == {
               %IR.IgnoredExpression{type: :module_attribute_definition},
               %Context{
                 module_attributes: %{
                   a: %IR.IntegerType{value: 1},
                   b: %IR.IntegerType{value: 4},
                   c: %IR.IntegerType{value: 3}
                 }
               }
             }
    end

    test "expression is a macro call" do
      ir = %IR.ModuleAttributeDefinition{
        name: :a,
        expression: %IR.Call{
          module: nil,
          function: :is_nil,
          args: [
            %IR.IntegerType{value: 999}
          ]
        }
      }

      assert {
               %IR.IgnoredExpression{type: :module_attribute_definition},
               %Context{
                 module_attributes: %{
                   a: %IR.BooleanType{value: false}
                 }
               }
             } = expand(ir, Context.new())
    end
  end

  describe "module definition" do
    test "top-level module" do
      ir = %IR.ModuleDefinition{
        module: %IR.Alias{segments: [:A, :B]},
        body: %IR.Block{
          expressions: [
            %IR.IntegerType{value: 1}
          ]
        }
      }

      assert expand(ir, %Context{}) ==
               {%IR.ModuleDefinition{
                  module: %IR.ModuleType{module: A.B, segments: [:A, :B]},
                  body: %IR.Block{
                    expressions: [
                      %IR.IntegerType{value: 1}
                    ]
                  }
                }, %Context{}}
    end

    test "nested module" do
      ir = %IR.ModuleDefinition{
        module: %IR.Alias{segments: [:A, :B]},
        body: %IR.Block{
          expressions: [
            %IR.ModuleDefinition{
              module: %IR.Alias{segments: [:C, :D]},
              body: %IR.Block{
                expressions: [
                  %IR.IntegerType{value: 1}
                ]
              }
            }
          ]
        }
      }

      assert expand(ir, %Context{}) ==
               {%IR.ModuleDefinition{
                  module: %IR.ModuleType{module: A.B, segments: [:A, :B]},
                  body: %IR.Block{
                    expressions: [
                      %IR.ModuleDefinition{
                        module: %IR.ModuleType{module: A.B.C.D, segments: [:A, :B, :C, :D]},
                        body: %IR.Block{
                          expressions: [
                            %IR.IntegerType{value: 1}
                          ]
                        }
                      }
                    ]
                  }
                }, %Context{}}
    end
  end

  # --- CONTROL FLOW ---

  describe "alias" do
    test "is defined in context" do
      ir = %IR.Alias{segments: [:Seg1]}

      assert expand(ir, @context_with_aliases) ==
               {%IR.ModuleType{module: Seg2.Seg3, segments: [:Seg2, :Seg3]},
                @context_with_aliases}
    end

    test "is not defined in context" do
      ir = %IR.Alias{segments: [:Seg4, :Seg5]}

      assert expand(ir, @context_with_aliases) ==
               {%IR.ModuleType{module: Seg4.Seg5, segments: [:Seg4, :Seg5]},
                @context_with_aliases}
    end
  end

  test "block" do
    ir = %IR.Block{
      expressions: [
        %IR.AliasDirective{alias_segs: [:A, :B], as: :C},
        %IR.Alias{segments: [:Z]},
        %IR.Alias{segments: [:C]}
      ]
    }

    context = %Context{aliases: %{Z: [:X, :Y]}}

    assert expand(ir, context) ==
             {%IR.Block{
                expressions: [
                  %IR.IgnoredExpression{type: :alias_directive},
                  %IR.ModuleType{module: X.Y, segments: [:X, :Y]},
                  %IR.ModuleType{module: A.B, segments: [:A, :B]}
                ]
              },
              %Context{
                aliases: %{Z: [:X, :Y]}
              }}
  end

  describe "call" do
    test "current module function called without alias" do
      args = [%IR.ModuleAttributeOperator{name: :a}, %IR.ModuleAttributeOperator{name: :c}]
      ir = %IR.Call{module: nil, function: :my_fun, args: args}
      context = %{@context_with_module_attributes | module: A.B}

      assert expand(ir, context) ==
               {[
                  %IR.FunctionCall{
                    module: %IR.ModuleType{module: A.B, segments: [:A, :B]},
                    function: :my_fun,
                    args: [
                      %IR.IntegerType{value: 1},
                      %IR.IntegerType{value: 3}
                    ],
                    erlang: false
                  }
                ], context}
    end

    test "imported function called without alias" do
      args = [%IR.ModuleAttributeOperator{name: :a}, %IR.ModuleAttributeOperator{name: :c}]
      ir = %IR.Call{module: nil, function: :my_fun, args: args}
      context = %{@context_with_module_attributes | functions: %{my_fun: %{2 => A.B}}}

      assert expand(ir, context) ==
               {[
                  %Hologram.Compiler.IR.FunctionCall{
                    module: %IR.ModuleType{module: A.B, segments: [:A, :B]},
                    function: :my_fun,
                    args: [
                      %IR.IntegerType{value: 1},
                      %IR.IntegerType{value: 3}
                    ],
                    erlang: false
                  }
                ], context}
    end

    test "function called with alias" do
      args = [%IR.ModuleAttributeOperator{name: :a}, %IR.ModuleAttributeOperator{name: :c}]

      ir = %IR.Call{
        module: %IR.Alias{segments: [:A, :B]},
        function: :my_fun,
        args: args
      }

      context = %{@context_with_module_attributes | aliases: %{A: [:C, :D]}}

      assert expand(ir, context) ==
               {[
                  %IR.FunctionCall{
                    module: %IR.ModuleType{
                      module: C.D.B,
                      segments: [:C, :D, :B]
                    },
                    function: :my_fun,
                    args: [
                      %IR.IntegerType{value: 1},
                      %IR.IntegerType{value: 3}
                    ],
                    erlang: false
                  }
                ], context}
    end

    test "macro called without alias or args, returning single expression which doesn't change the context" do
      ir = %IR.Call{module: nil, function: :macro_2a, args: []}

      context = %Context{
        macros: %{macro_2a: %{0 => Hologram.Test.Fixtures.Compiler.Expander.Module2}}
      }

      assert expand(ir, context) == {[%IR.IntegerType{value: 123}], context}
    end

    test "macro called with alias" do
      alias_ir = %IR.Alias{
        segments: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module2]
      }

      call_ir = %IR.Call{
        module: alias_ir,
        function: :macro_2a,
        args: []
      }

      assert expand(call_ir, @context_dummy) == {[%IR.IntegerType{value: 123}], @context_dummy}
    end

    test "macro called with args" do
      alias_ir = %IR.Alias{
        segments: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module2]
      }

      args = [%IR.Symbol{name: :x}, %IR.Symbol{name: :y}]

      call_ir = %IR.Call{
        module: alias_ir,
        function: :macro_2d,
        args: args
      }

      context = %Context{variables: MapSet.new([:x, :y])}

      assert expand(call_ir, context) ==
               {[
                  %IR.AdditionOperator{
                    left: %IR.Variable{name: :x},
                    right: %IR.Variable{name: :y}
                  }
                ], context}
    end

    test "macro returning multiple expressions" do
      ir = %IR.Call{module: nil, function: :macro_2b, args: []}

      context = %Context{
        macros: %{macro_2b: %{0 => Hologram.Test.Fixtures.Compiler.Expander.Module2}}
      }

      assert expand(ir, context) ==
               {[%IR.IntegerType{value: 100}, %IR.IntegerType{value: 200}], context}
    end

    test "macro which changes the context (adds an alias)" do
      ir = %IR.Call{module: nil, function: :macro_2c, args: []}

      context = %Context{
        macros: %{macro_2c: %{0 => Hologram.Test.Fixtures.Compiler.Expander.Module2}}
      }

      assert expand(ir, context) ==
               {[%IR.IgnoredExpression{type: :alias_directive}],
                %{context | aliases: %{C: [:A, :B]}}}
    end

    #   test "nested single expression macros, with parenthesis" do
    #     ir = %IR.Call{module: nil, function: :macro_3a, args: []}

    #     context = %Context{
    #       macros: %{macro_3a: %{0 => Hologram.Test.Fixtures.Compiler.Expander.Module3}},
    #       module: A.B
    #     }

    #     result = Expander.expand(ir, context)
    #     expected = {[%IR.IntegerType{value: 123}], context}

    #     assert result == expected
    #   end

    #   test "nested macros without parenthesis" do
    #     ir = %IR.Call{module: nil, function: :macro_3b, args: []}

    #     context = %Context{
    #       macros: %{macro_3b: %{0 => Hologram.Test.Fixtures.Compiler.Expander.Module3}},
    #       module: A.B
    #     }

    #     result = Expander.expand(ir, context)
    #     expected = {[%IR.IntegerType{value: 123}], context}

    #     assert result == expected
    #   end

    #   test "nested multiple expressions macros" do
    #     ir = %IR.Call{module: nil, function: :macro_3c, args: []}

    #     context = %Context{
    #       macros: %{macro_3c: %{0 => Hologram.Test.Fixtures.Compiler.Expander.Module3}},
    #       module: A.B
    #     }

    #     result = Expander.expand(ir, context)

    #     expected =
    #       {[
    #          %IR.IntegerType{value: 100},
    #          %IR.IntegerType{value: 200},
    #          %IR.IntegerType{value: 300}
    #        ], context}

    #     assert result == expected
    #   end
  end

  test "function call" do
    ir = %IR.FunctionCall{
      module: A.B,
      function: :my_fun,
      args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]
    }

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  describe "symbol" do
    test "variable" do
      context = %Context{variables: MapSet.new([:a])}
      ir = %IR.Symbol{name: :a}

      assert expand(ir, context) == {%IR.Variable{name: :a}, context}
    end

    test "call" do
      context = %Context{module: A.B}
      ir = %IR.Symbol{name: :a}

      assert expand(ir, context) ==
               {[
                  %IR.FunctionCall{
                    module: %IR.ModuleType{module: A.B, segments: [:A, :B]},
                    function: :a,
                    args: []
                  }
                ], context}
    end
  end

  test "variable" do
    ir = %IR.Variable{name: :a}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  # --- BINDINGS ---

  test "binding" do
    ir = %IR.Binding{
      name: :x,
      access_path: [%IR.MatchAccess{}, %IR.MapAccess{key: %IR.Alias{segments: [:A, :B]}}]
    }

    assert expand(ir, @context_dummy) ==
             {%IR.Binding{
                name: :x,
                access_path: [
                  %IR.MatchAccess{},
                  %IR.MapAccess{
                    key: %IR.ModuleType{module: A.B, segments: [:A, :B]}
                  }
                ]
              }, @context_dummy}
  end

  test "list index access" do
    ir = %IR.ListIndexAccess{index: 0}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  test "map access" do
    ir = %IR.MapAccess{key: %IR.Alias{segments: [:A, :B]}}

    assert expand(ir, @context_dummy) ==
             {%IR.MapAccess{key: %IR.ModuleType{module: A.B, segments: [:A, :B]}}, @context_dummy}
  end

  test "match access" do
    ir = %IR.MatchAccess{}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  # --- OTHER IR ---

  test "ignored expression" do
    ir = %IR.IgnoredExpression{type: :alias_directive}

    assert expand(ir, @context_dummy) == {ir, @context_dummy}
  end

  # @context %Context{
  #   aliases: %{Seg1: [:Seg2, :Seg3]},
  #   module_attributes: %{
  #     a: %IR.IntegerType{value: 1},
  #     c: %IR.IntegerType{value: 3}
  #   }
  # }
end
