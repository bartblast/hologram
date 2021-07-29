defmodule Hologram.Compiler.FunctionDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, FunctionDefinitionTransformer}
  alias Hologram.Compiler.IR.{AccessOperator, AtomType, FunctionDefinition, IntegerType, Variable}

  @context %Context{module: Abc}

  describe "transform/4" do
    test "name" do
      # def test(1, 2) do
      # end

      name = :test
      params = [1, 2]
      body = []

      assert %FunctionDefinition{name: :test} =
              FunctionDefinitionTransformer.transform(name, params, body, @context)
    end

    test "arity" do
      # def test(1, 2) do
      # end

      name = :test
      params = [1, 2]
      body = []

      assert %FunctionDefinition{arity: 2} =
              FunctionDefinitionTransformer.transform(name, params, body, @context)
    end

    test "params" do
      # def test(a, b) do
      # end

      name = :test
      params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]
      body = []

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

      expected = [
        %Variable{name: :a},
        %Variable{name: :b}
      ]

      assert result.params == expected
    end

    test "bindings" do
      # def test(1, %{a: x, b: y}) do
      # end

      name = :test
      params = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}, b: {:y, [line: 2], nil}]}]
      body = []

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

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
      # def test do
      #   1
      # end

      name = :test
      params = nil
      body = [1]

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

      assert result.body == [%IntegerType{value: 1}]
    end

    test "body, multiple expressions" do
      # def test do
      #   1
      #   2
      # end

      name = :test
      params = nil
      body = [1, 2]

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

      expected = [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]

      assert result.body == expected
    end
  end

  describe "aggregate_bindings/1" do
    test "no bindings" do
      # def test(1, 2) do
      # end

      params_ast = [1, 2]
      params = FunctionDefinitionTransformer.transform_params(params_ast, @context)
      result = FunctionDefinitionTransformer.aggregate_bindings(params)

      assert result == []
    end

    test "single binding in single param" do
      # def test(1, %{a: x}) do
      # end

      params_ast = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}]}]
      params = FunctionDefinitionTransformer.transform_params(params_ast, @context)
      result = FunctionDefinitionTransformer.aggregate_bindings(params)

      expected = [
        x:
          {1,
           [
             %AccessOperator{
               key: %AtomType{value: :a}
             },
             %Variable{name: :x}
           ]}
      ]

      assert result == expected
    end

    test "multiple bindings in single param" do
      # def test(1, %{a: x, b: y}) do
      # end

      params_ast = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}, b: {:y, [line: 2], nil}]}]
      params = FunctionDefinitionTransformer.transform_params(params_ast, @context)
      result = FunctionDefinitionTransformer.aggregate_bindings(params)

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

      assert result == expected
    end

    test "multiple bindings in multiple params" do
      # def test(1, %{a: k, b: m}, 2, %{c: s, d: t}) do
      # end

      params_ast = [
        1,
        {:%{}, [line: 2], [a: {:k, [line: 2], nil}, b: {:m, [line: 2], nil}]},
        2,
        {:%{}, [line: 2], [c: {:s, [line: 2], nil}, d: {:t, [line: 2], nil}]}
      ]

      params = FunctionDefinitionTransformer.transform_params(params_ast, @context)
      result = FunctionDefinitionTransformer.aggregate_bindings(params)

      expected = [
        k:
          {1,
           [
             %AccessOperator{
               key: %AtomType{value: :a}
             },
             %Variable{name: :k}
           ]},
        m:
          {1,
           [
             %AccessOperator{
               key: %AtomType{value: :b}
             },
             %Variable{name: :m}
           ]},
        s:
          {3,
           [
             %AccessOperator{
               key: %AtomType{value: :c}
             },
             %Variable{name: :s}
           ]},
        t:
          {3,
           [
             %AccessOperator{
               key: %AtomType{value: :d}
             },
             %Variable{name: :t}
           ]}
      ]

      assert result == expected
    end

    test "sorting" do
      # def test(y, z) do
      # end

      params_ast = [{:y, [line: 2], nil}, {:x, [line: 2], nil}]
      params = FunctionDefinitionTransformer.transform_params(params_ast, @context)
      result = FunctionDefinitionTransformer.aggregate_bindings(params)

      expected = [
        x:
          {1,
           [
             %Variable{name: :x}
           ]},
        y:
          {0,
           [
             %Variable{name: :y}
           ]}
      ]

      assert result == expected
    end
  end

  describe "transform_params/2" do
    test "no params" do
      # def test do
      # end

      params = nil
      result = FunctionDefinitionTransformer.transform_params(params, @context)

      assert result == []
    end

    test "vars" do
      # def test(a, b) do
      # end

      params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]
      result = FunctionDefinitionTransformer.transform_params(params, @context)

      expected = [
        %Variable{name: :a},
        %Variable{name: :b}
      ]

      assert result == expected
    end

    test "primitive types" do
      # def test(:a, 2) do
      # end

      params = [:a, 2]
      result = FunctionDefinitionTransformer.transform_params(params, @context)

      expected = [
        %AtomType{value: :a},
        %IntegerType{value: 2}
      ]

      assert result == expected
    end
  end
end
