defmodule Hologram.Compiler.TransformerTest do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module1
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2

  describe "call, AST obtained directly from source file" do
    # direct call, without args, without parenthesis case is tested as part of the symbol tests

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
end
