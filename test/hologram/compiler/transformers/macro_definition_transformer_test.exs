defmodule Hologram.Compiler.MacroDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, MacroDefinitionTransformer}
  alias Hologram.Compiler.IR.{AccessOperator, AtomType, MacroDefinition, Variable}

  @context %Context{module: Abc}

  describe "transform/4" do
    test "name" do
      # defmacro test(1, 2) do
      # end

      name = :test
      params = [1, 2]
      body = []

      assert %MacroDefinition{name: :test} =
        MacroDefinitionTransformer.transform(name, params, body, @context)
    end

    test "arity" do
      # defmacro test(1, 2) do
      # end

      name = :test
      params = [1, 2]
      body = []

      assert %MacroDefinition{arity: 2} =
              MacroDefinitionTransformer.transform(name, params, body, @context)
    end

    test "params" do
      # defmacro test(a, b) do
      # end

      name = :test
      params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]
      body = []

      assert %MacroDefinition{} =
               result = MacroDefinitionTransformer.transform(name, params, body, @context)

      expected = [
        %Variable{name: :a},
        %Variable{name: :b}
      ]

      assert result.params == expected
    end

    test "bindings" do
      # defmacro test(1, %{a: x, b: y}) do
      # end

      name = :test
      params = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}, b: {:y, [line: 2], nil}]}]
      body = []

      assert %MacroDefinition{} =
               result = MacroDefinitionTransformer.transform(name, params, body, @context)

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
      # defmacro test do
      #   quote do 1 end
      # end

      name = :test
      params = nil
      body = [{:quote, [line: 2], [[do: {:__block__, [], [1]}]]}]

      assert %MacroDefinition{} =
               result = MacroDefinitionTransformer.transform(name, params, body, @context)

      assert result.body == body
    end

    test "body, multiple expressions" do
      # def test do
      #   1
      #   2
      # end

      name = :test
      params = nil

      body = [
        {:quote, [line: 2], [[do: {:__block__, [], [1]}]]},
        {:quote, [line: 3], [[do: {:__block__, [], [2]}]]}
      ]

      assert %MacroDefinition{} =
               result = MacroDefinitionTransformer.transform(name, params, body, @context)

      assert result.body == body
    end
  end
end
