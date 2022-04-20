defmodule Hologram.Compiler.MacroDefinitionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, MacroDefinitionTransformer}

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    Block,
    IntegerType,
    MacroDefinition,
    MapAccess,
    ParamAccess,
    Variable
  }

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
        %Binding{
          name: :x,
          access_path: [
            %ParamAccess{index: 1},
            %MapAccess{key: %AtomType{value: :a}}
          ]
        },
        %Binding{
          name: :y,
          access_path: [
            %ParamAccess{index: 1},
            %MapAccess{key: %AtomType{value: :b}}
          ]
        }
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

      expected = %Block{expressions: [
        %IntegerType{value: 1}
      ]}

      assert result.body == expected
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

      expected = %Block{expressions: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]}

      assert result.body == expected
    end
  end
end
