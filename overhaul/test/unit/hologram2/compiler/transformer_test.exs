defmodule Hologram.Compiler.TransformerTest do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module1
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2

  describe "alias / module type" do
    test "AST obtained directly from source file" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert transform(ast) == %IR.Alias{segments: [:Aaa, :Bbb]}
    end

    test "AST returned from macro, not an inner alias" do
      # apply(Module1, :"MACRO-macro_alias_1", [__ENV__])
      ast = {:__aliases__, [alias: false], [:Aaa, :Bbb]}

      assert transform(ast) == %IR.Alias{segments: [:Aaa, :Bbb]}
    end

    test "AST returned from macro, an inner alias" do
      # apply(Module1, :"MACRO-macro_alias_2", [__ENV__])
      ast = {:__aliases__, [alias: Module2], [:InnerAlias]}

      assert transform(ast) == %IR.ModuleType{
               module: Module2,
               segments: [:Hologram, :Test, :Fixtures, :Compiler, :Transformer, :Module2]
             }
    end
  end

  describe "anonymous function call, AST obtained directly from source file" do
    test "without args" do
      # test.()
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], []}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: []
             }
    end

    test "with args" do
      # test.(1, 2)
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "anonymous function call, AST returned from macro" do
    test "without args" do
      # apply(Module1, :"MACRO-macro_anonymous_function_call_1", [__ENV__])
      ast = {{:., [], [{:test, [], Module1}]}, [], []}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: []
             }
    end

    test "with args" do
      # apply(Module1, :"MACRO-macro_anonymous_function_call_2", [__ENV__])
      ast = {{:., [], [{:test, [], Module1}]}, [], [1, 2]}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "call, AST obtained directly from source file" do
    # direct call, without args, without parenthesis case is tested as part of the symbol tests

    test "direct, without args, with parenthesis" do
      # my_fun()
      ast = {:my_fun, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :my_fun,
               args: []
             }
    end

    test "direct, with args" do
      # my_fun(1, 2)
      ast = {:my_fun, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # call on symbol, without args, without parenthesis case is tested as part of the dot operator tests

    test "on symbol, without args, with parenthesis" do
      # a.x()
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.Symbol{name: :a},
               function: :x,
               args: []
             }
    end

    test "on symbol, with args" do
      # a.x(1, 2)
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.Symbol{name: :a},
               function: :x,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on alias, without args, without parenthesis" do
      # Abc.my_fun
      ast =
        {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]},
         [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Abc]},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, without args, with parenthesis" do
      # Abc.my_fun()
      ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Abc]},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, with args" do
      # Abc.my_fun(1, 2)
      ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Abc]},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # call on module attribute, without args, without parenthesis case is tested as part of the dot operator tests

    test "on module attribute, without args" do
      # @my_attr.my_fun()
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:my_attr, [line: 1], nil}]}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: []
             }
    end

    test "on module attribute, with args" do
      # @my_attr.my_fun(1, 2)
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:my_attr, [line: 1], nil}]}, :my_fun]}, [line: 1],
         [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    # call on expression, without args, without parenthesis case is tested as part of the dot operator tests

    # TODO: uncomment after addition operator transformer is implemented
    # test "on expression, without args" do
    #   # (3 + 4).my_fun()
    #   ast = {{:., [line: 1], [{:+, [line: 1], [3, 4]}, :my_fun]}, [line: 1], []}

    #   assert transform(ast) == %IR.Call{
    #            module: %IR.AdditionOperator{
    #              left: %IR.IntegerType{value: 3},
    #              right: %IR.IntegerType{value: 4}
    #            },
    #            function: :my_fun,
    #            args: []
    #          }
    # end

    # TODO: uncomment after addition operator transformer is implemented
    # test "on expression, with args" do
    #   # (3 + 4).my_fun(1, 2)
    #   ast = {{:., [line: 1], [{:+, [line: 1], [3, 4]}, :my_fun]}, [line: 1], [1, 2]}

    #   assert transform(ast) == %IR.Call{
    #            module: %IR.AdditionOperator{
    #              left: %IR.IntegerType{value: 3},
    #              right: %IR.IntegerType{value: 4}
    #            },
    #            function: :my_fun,
    #            args: [
    #              %IR.IntegerType{value: 1},
    #              %IR.IntegerType{value: 2}
    #            ]
    #          }
    # end

    test "on __MODULE__ pseudo-variable, without args, without parenthesis" do
      # __MODULE__.my_fun
      ast =
        {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :my_fun]}, [no_parens: true, line: 1],
         []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModulePseudoVariable{},
               function: :my_fun,
               args: []
             }
    end

    test "on __MODULE__ pseudo-variable, without args, with parenthesis" do
      # __MODULE__.my_fun()
      ast = {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModulePseudoVariable{},
               function: :my_fun,
               args: []
             }
    end

    test "on __MODULE__ pseudo-variable, with args" do
      # __MODULE__.my_fun(1, 2)
      ast = {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.ModulePseudoVariable{},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  describe "dot operator, AST obtained directly from source file" do
    test "on symbol" do
      # abc.x
      ast = {{:., [line: 1], [{:abc, [line: 1], nil}, :x]}, [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.Symbol{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end

    test "on module attribute" do
      # @abc.x
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:abc, [line: 1], nil}]}, :x]},
         [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.ModuleAttributeOperator{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end

    test "on expression" do
      # (3 + 4).x
      ast = {{:., [line: 1], [{:+, [line: 1], [3, 4]}, :x]}, [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.Call{
                 module: nil,
                 function: :+,
                 args: [
                   %IR.IntegerType{value: 3},
                   %IR.IntegerType{value: 4}
                 ]
               },
               right: %IR.AtomType{value: :x}
             }
    end
  end

  describe "dot operator, AST returned from macro" do
    test "on symbol" do
      # apply(Module1, :"MACRO-macro_dot_operator_1", [__ENV__])
      ast = {{:., [], [{:abc, [], Module1}, :x]}, [no_parens: true], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.Symbol{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end

    test "on module attribute" do
      # apply(Module1, :"MACRO-macro_dot_operator_2", [__ENV__])
      ast =
        {{:., [],
          [
            {:@, [context: Module1, imports: [{1, Kernel}]],
             [{:abc, [context: Module1], Module1}]},
            :x
          ]}, [no_parens: true], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.ModuleAttributeOperator{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end

    test "on expression" do
      # apply(Module1, :"MACRO-macro_dot_operator_3", [__ENV__])
      ast =
        {{:., [], [{:+, [context: Module1, imports: [{1, Kernel}, {2, Kernel}]], [3, 4]}, :x]},
         [no_parens: true], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.Call{
                 module: nil,
                 function: :+,
                 args: [
                   %IR.IntegerType{value: 3},
                   %IR.IntegerType{value: 4}
                 ]
               },
               right: %IR.AtomType{value: :x}
             }
    end
  end

  test "float type" do
    # 1.0
    ast = 1.0

    assert transform(ast) == %IR.FloatType{value: 1.0}
  end

  test "integer type" do
    # 1
    ast = 1

    assert transform(ast) == %IR.IntegerType{value: 1}
  end

  test "list type" do
    # [1, 2]
    ast = [1, 2]

    assert transform(ast) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  describe "module attribute definition" do
    @expected_ir %IR.ModuleAttributeDefinition{
      name: :my_attr,
      expression: %IR.IntegerType{value: 987}
    }

    test "AST obtained directly from source file" do
      # @my_attr 987
      ast = {:@, [line: 1], [{:my_attr, [line: 1], [987]}]}

      assert transform(ast) == @expected_ir
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_attribute_definition", [__ENV__])
      ast =
        {:@, [context: Module1, imports: [{1, Kernel}]], [{:my_attr, [context: Module1], [987]}]}

      assert transform(ast) == @expected_ir
    end
  end

  describe "module attribute operator" do
    @expected_ir %IR.ModuleAttributeOperator{name: :my_attr}

    test "AST obtained directly from source file" do
      # @my_attr
      ast = {:@, [line: 1], [{:my_attr, [line: 1], nil}]}

      assert transform(ast) == @expected_ir
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_attribute_operator", [__ENV__])
      ast =
        {:@, [context: Module1, imports: [{1, Kernel}]],
         [{:my_attr, [context: Module1], Module1}]}

      assert transform(ast) == @expected_ir
    end
  end

  describe "__MODULE__ pseudo-variable" do
    test "AST obtained directly from source file" do
      # __MODULE__
      ast = {:__MODULE__, [line: 1], nil}

      assert transform(ast) == %IR.ModulePseudoVariable{}
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_pseudo_variable", [__ENV__])
      ast = {:__MODULE__, [], Module1}

      assert transform(ast) == %IR.ModulePseudoVariable{}
    end
  end

  describe "symbol" do
    @expected_ir %IR.Symbol{name: :my_symbol}

    test "AST obtained directly from source file" do
      # my_symbol
      ast = {:my_symbol, [line: 1], nil}

      assert transform(ast) == @expected_ir
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_symbol", [__ENV__])
      ast = {:my_symbol, [], Module1}

      assert transform(ast) == @expected_ir
    end
  end

  describe "tuple type" do
    test "2-element tuple" do
      # {1, 2}
      ast = {1, 2}

      assert transform(ast) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "non-2-element tuple" do
      # {1, 2, 3}
      ast = {:{}, [line: 1], [1, 2, 3]}

      assert transform(ast) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end
end
