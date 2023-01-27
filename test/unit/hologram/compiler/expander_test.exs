defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Expander
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Expander.Module1

  @context %Context{
    aliases: %{Seg1: [:Seg2, :Seg3]},
    module_attributes: %{
      a: %IR.IntegerType{value: 1},
      c: %IR.IntegerType{value: 3}
    }
  }

  test "basic data type" do
    ir = %IR.IntegerType{value: 123}
    result = Expander.expand(ir, @context)

    assert result == {ir, @context}
  end

  test "basic binary operator" do
    ir = %IR.AdditionOperator{
      left: %IR.ModuleAttributeOperator{name: :a},
      right: %IR.ModuleAttributeOperator{name: :c}
    }

    result = Expander.expand(ir, @context)

    assert result ==
             {%IR.AdditionOperator{
                left: %IR.IntegerType{value: 1},
                right: %IR.IntegerType{value: 3}
              }, @context}
  end

  test "binding index access" do
    ir = %IR.ListIndexAccess{index: 0}
    result = Expander.expand(ir, @context)

    assert result == {ir, @context}
  end

  describe "alias" do
    test "has mapping" do
      ir = %IR.Alias{segments: [:Seg1]}

      result = Expander.expand(ir, @context)
      expected = {%IR.ModuleType{module: Seg2.Seg3, segments: [:Seg2, :Seg3]}, @context}

      assert expected == result
    end

    test "doesn't have mapping" do
      ir = %IR.Alias{segments: [:Seg4, :Seg5]}

      result = Expander.expand(ir, @context)
      expected = {%IR.ModuleType{module: Seg4.Seg5, segments: [:Seg4, :Seg5]}, @context}

      assert expected == result
    end
  end

  describe "alias directive" do
    test "which doesn't use any other alias" do
      ir = %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
      result = Expander.expand(ir, @context)

      expected_aliases = Map.put(@context.aliases, :C, [:A, :B])
      expected = {%IR.IgnoredExpression{}, %{@context | aliases: expected_aliases}}

      assert result == expected
    end

    test "which uses an alias defined before it" do
      aliases = Map.put(@context.aliases, :C, [:A, :B])
      context = %{@context | aliases: aliases}

      ir = %IR.AliasDirective{alias_segs: [:C, :D], as: :E}
      result = Expander.expand(ir, context)

      expected_aliases = Map.put(context.aliases, :E, [:A, :B, :D])
      expected = {%IR.IgnoredExpression{}, %{context | aliases: expected_aliases}}

      assert result == expected
    end

    test "which uses an alias defined after it" do
      aliases = Map.put(@context.aliases, :E, [:C, :D])
      context = %{@context | aliases: aliases}

      ir = %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
      result = Expander.expand(ir, context)

      expected_aliases = Map.put(context.aliases, :C, [:A, :B])
      expected = {%IR.IgnoredExpression{}, %{context | aliases: expected_aliases}}

      assert result == expected
    end
  end

  test "binding" do
    ir = %IR.Binding{
      name: :x,
      access_path: [%IR.MatchAccess{}, %IR.MapAccess{key: %IR.Alias{segments: [:A, :B]}}]
    }

    result = Expander.expand(ir, @context)

    expected =
      {%IR.Binding{
         name: :x,
         access_path: [
           %IR.MatchAccess{},
           %IR.MapAccess{
             key: %IR.ModuleType{module: A.B, segments: [:A, :B]}
           }
         ]
       }, @context}

    assert result == expected
  end

  test "block" do
    ir = %IR.Block{
      expressions: [
        %IR.Alias{segments: [:A]},
        %IR.Alias{segments: [:B]}
      ]
    }

    result = Expander.expand(ir, @context)

    assert {
             %IR.Block{
               expressions: [
                 %IR.ModuleType{module: A, segments: [:A]},
                 %IR.ModuleType{module: B, segments: [:B]}
               ]
             },
             _context
           } = result
  end

  describe "import directive" do
    test "no opts" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: [],
        except: []
      }

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{fun_2: %{1 => Module1}}
      assert context.macros == %{macro_3: %{2 => Module1}}
    end

    test "'except' opt" do
      ir = %IR.ImportDirective{
        alias_segs: [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1],
        only: [],
        except: [fun_2: 1, macro_3: 2]
      }

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

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

      result = Expander.expand(ir, @context)
      assert {%IR.IgnoredExpression{}, %Context{} = context} = result

      assert context.functions == %{sigil_a: %{2 => Module1}}
      assert context.macros == %{sigil_c: %{2 => Module1}}
    end
  end

  test "map access" do
    ir = %IR.MapAccess{key: %IR.Alias{segments: [:A, :B]}}

    result = Expander.expand(ir, @context)
    expected = {%IR.MapAccess{key: %IR.ModuleType{module: A.B, segments: [:A, :B]}}, @context}

    assert result == expected
  end

  test "map type" do
    ir = %IR.MapType{
      data: [
        {%IR.Alias{segments: [:A]}, %IR.Alias{segments: [:B]}},
        {%IR.Alias{segments: [:C]}, %IR.Alias{segments: [:D]}}
      ]
    }

    result = Expander.expand(ir, @context)

    expected =
      {%IR.MapType{
         data: [
           {%IR.ModuleType{module: A, segments: [:A]}, %IR.ModuleType{module: B, segments: [:B]}},
           {%IR.ModuleType{module: C, segments: [:C]}, %IR.ModuleType{module: D, segments: [:D]}}
         ]
       }, @context}

    assert result == expected
  end

  test "match access" do
    ir = %IR.MatchAccess{}
    result = Expander.expand(ir, @context)

    assert result == {ir, @context}
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

    context = %{@context | variables: MapSet.new([:m, :n])}
    result = Expander.expand(ir, context)

    expected_context = %{@context | variables: MapSet.new([:m, :n, :x, :y])}

    expected =
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
       }, expected_context}

    assert result == expected
  end

  describe "module attribute definition" do
    test "expression which doesn't use module attributes" do
      ir = %IR.ModuleAttributeDefinition{
        name: :b,
        expression: %IR.AdditionOperator{
          left: %IR.IntegerType{value: 5},
          right: %IR.IntegerType{value: 6}
        }
      }

      result = Expander.expand(ir, @context)

      assert {
               %IR.IgnoredExpression{},
               %Context{
                 module_attributes: %{
                   a: %IR.IntegerType{value: 1},
                   b: %IR.IntegerType{value: 11},
                   c: %IR.IntegerType{value: 3}
                 }
               }
             } = result
    end

    test "expression which uses module attributes" do
      ir = %IR.ModuleAttributeDefinition{
        name: :b,
        expression: %IR.AdditionOperator{
          left: %IR.ModuleAttributeOperator{name: :a},
          right: %IR.ModuleAttributeOperator{name: :c}
        }
      }

      result = Expander.expand(ir, @context)

      assert {
               %IR.IgnoredExpression{},
               %Context{
                 module_attributes: %{
                   a: %IR.IntegerType{value: 1},
                   b: %IR.IntegerType{value: 4},
                   c: %IR.IntegerType{value: 3}
                 }
               }
             } = result
    end
  end

  test "module attribute operator" do
    ir = %IR.ModuleAttributeOperator{name: :c}
    result = Expander.expand(ir, @context)

    assert result == {%IR.IntegerType{value: 3}, @context}
  end

  describe "module def" do
    test "top-level module" do
      ir = %IR.ModuleDefinition{
        module: %IR.Alias{segments: [:A, :B]},
        body: %IR.Block{
          expressions: [
            %IR.IntegerType{value: 1}
          ]
        }
      }

      result = Expander.expand(ir, @context)

      expected =
        {%IR.ModuleDefinition{
           module: %IR.ModuleType{module: A.B, segments: [:A, :B]},
           body: %IR.Block{
             expressions: [
               %IR.IntegerType{value: 1}
             ]
           }
         }, @context}

      assert result == expected
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

      result = Expander.expand(ir, @context)

      expected =
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
         }, @context}

      assert result == expected
    end
  end

  test "module pseudo-variable" do
    ir = %IR.ModulePseudoVariable{}
    module = %IR.ModuleType{module: A.B, segments: [:A, :B]}
    context = %{@context | module: module}
    result = Expander.expand(ir, context)

    assert result == {module, context}
  end

  test "module type" do
    ir = %IR.ModuleType{module: A.B, segments: [:A, :B]}
    result = Expander.expand(ir, @context)

    assert result == {ir, @context}
  end

  test "variable" do
    ir = %IR.Variable{name: :a}
    result = Expander.expand(ir, @context)

    assert result == {ir, @context}
  end
end
