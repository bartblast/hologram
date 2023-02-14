defmodule Hologram.Compiler.DotOperatorTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.DotOperatorTransformer
  alias Hologram.Compiler.IR.AccessOperator
  alias Hologram.Compiler.IR.AdditionOperator
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.AtomType
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.ModulePseudoVariable
  alias Hologram.Compiler.IR.Symbol

  describe "dot operator on symbol" do
    test "with parenthesis, without arguments" do
      code = "a.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end

    test "with parenthesis, with arguments" do
      code = "a.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end
  end

  describe "dot operator on alias" do
    test "with parenthesis, without arguments" do
      code = "Abc.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end

    test "with parenthesis, with arguments" do
      code = "Abc.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end
  end

  describe "dot operator on module attribute" do
    test "with parenthesis, without arguments" do
      code = "@abc.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end

    test "with parenthesis, with arguments" do
      code = "@abc.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end
  end

  describe "dot operator on expression" do
    test "with parenthesis, without arguments" do
      code = "(3 + 4).x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end

    test "with parenthesis, with arguments" do
      code = "(3 + 4).x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end
  end

  describe "dot operator on __MODULE__ pseudo-variable" do
    test "with parenthesis, without arguments" do
      code = "__MODULE__.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end

    test "with parenthesis, with arguments" do
      code = "__MODULE__.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end
  end

  describe "Erlang function call" do
    test "without parenthesis" do
      code = ":my_module.x"
      ast = ast(code)
      result = DotOperatorTransformer.transform(ast)

      expected = %DotOperator{
        left: %AtomType{value: :my_module},
        right: %AtomType{value: :x}
      }

      assert result == expected
    end

    test "with parenthesis, without arguments" do
      code = ":my_module.x()"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end

    test "with parenthesis, with arguments" do
      code = ":my_module.x(1, 2)"
      ast = ast(code)

      assert %Call{} = DotOperatorTransformer.transform(ast)
    end
  end

  test "string interpolation" do
    code = ~S("#{test}")
    {_, _, [{_, _, [ast, _]}]} = ast(code)

    assert %Call{} = DotOperatorTransformer.transform(ast)
  end
end

test "on alias" do
  # Abc.x
  ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :x]}, [no_parens: true, line: 1], []}

  assert transform(ast) == %IR.DotOperator{
           left: %IR.Alias{segments: [:Abc]},
           right: %IR.AtomType{value: :x}
         }
end

test "on __MODULE__ pseudo-variable" do
  # __MODULE__.x
  ast = {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :x]}, [no_parens: true, line: 1], []}

  assert transform(ast) == %IR.DotOperator{
           left: %IR.ModulePseudoVariable{},
           right: %IR.AtomType{value: :x}
         }
end
