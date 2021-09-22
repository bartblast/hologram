defmodule Hologram.Compiler.MacroDefinitionTransformerTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.{Context, MacroDefinitionTransformer}
  alias Hologram.Compiler.IR.{AccessOperator, AtomType, IntegerType, MacroDefinition, Variable}

  @context %Context{module: Abc}

  describe "transform/2" do
    test "module" do
      code = "defmacro test(1, 2) do end"
      ast = ast(code)

      assert %MacroDefinition{module: Abc} = MacroDefinitionTransformer.transform(ast, @context)
    end

    test "name" do
      code = "defmacro test(1, 2) do end"
      ast = ast(code)

      assert %MacroDefinition{name: :test} = MacroDefinitionTransformer.transform(ast, @context)
    end

    test "arity" do
      code = "defmacro test(1, 2) do end"
      ast = ast(code)

      assert %MacroDefinition{arity: 2} = MacroDefinitionTransformer.transform(ast, @context)
    end

    test "params" do
      code = "defmacro test(a, b) do end"
      ast = ast(code)

      assert %MacroDefinition{} = result = MacroDefinitionTransformer.transform(ast, @context)

      expected = [
        %Variable{name: :a},
        %Variable{name: :b}
      ]

      assert result.params == expected
    end

    test "bindings" do
      code = "defmacro test(1, %{a: x, b: y}) do end"
      ast = ast(code)

      assert %MacroDefinition{} = result = MacroDefinitionTransformer.transform(ast, @context)

      expected = [
        x:
          {1,
           [
             %AccessOperator{
               key: %AtomType{value: :a}
             },
             %Variable{name: :x}
           ]},
        y:
          {1,
           [
             %AccessOperator{
               key: %AtomType{value: :b}
             },
             %Variable{name: :y}
           ]}
      ]

      assert result.bindings == expected
    end

    test "body, single expression" do
      code = """
      defmacro test do
        1
      end
      """

      ast = ast(code)

      assert %MacroDefinition{} = result = MacroDefinitionTransformer.transform(ast, @context)
      assert result.body == [%IntegerType{value: 1}]
    end

    test "body, multiple expressions" do
      code = """
      defmacro test do
        1
        2
      end
      """

      ast = ast(code)

      assert %MacroDefinition{} = result = MacroDefinitionTransformer.transform(ast, @context)
      assert result.body == [%IntegerType{value: 1}, %IntegerType{value: 2}]
    end
  end
end
