defmodule Hologram.Compiler.FunctionDefinitionTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, FunctionDefinitionTransformer}
  alias Hologram.Compiler.IR.{AccessOperator, AtomType, FunctionDefinition, IntegerType, Variable}

  @context %Context{
    module: Abc,
    uses: [],
    imports: [],
    aliases: [],
    attributes: []
  }

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

  describe "params" do
    test "no params" do
      # def test do
      # end

      name = :test
      params = nil
      body = []

      assert %FunctionDefinition{params: []} =
               FunctionDefinitionTransformer.transform(name, params, body, @context)
    end

    test "vars" do
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

    test "primitive types" do
      # def test(:a, 2) do
      # end

      name = :test
      params = [:a, 2]
      body = []

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

      expected = [
        %AtomType{value: :a},
        %IntegerType{value: 2}
      ]

      assert result.params == expected
    end
  end

  describe "bindings" do
    test "no bindings" do
      # def test(1, 2) do
      # end

      name = :test
      params = [1, 2]
      body = []

      assert %FunctionDefinition{bindings: []} =
               FunctionDefinitionTransformer.transform(name, params, body, @context)
    end

    test "single binding in single param" do
      # def test(1, %{a: x}) do
      # end

      name = :test
      params = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}]}]
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
           ]}
      ]

      assert result.bindings == expected
    end

    test "multiple bindings in single param" do
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

    test "multiple bindings in multiple params" do
      # def test(1, %{a: k, b: m}, 2, %{c: s, d: t}) do
      # end

      name = :test
      body = []

      params = [
        1,
        {:%{}, [line: 2], [a: {:k, [line: 2], nil}, b: {:m, [line: 2], nil}]},
        2,
        {:%{}, [line: 2], [c: {:s, [line: 2], nil}, d: {:t, [line: 2], nil}]}
      ]

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

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

      assert result.bindings == expected
    end

    test "sorting" do
      # def test(y, z) do
      # end

      name = :test
      params = [{:y, [line: 2], nil}, {:x, [line: 2], nil}]
      body = []

      assert %FunctionDefinition{} =
               result = FunctionDefinitionTransformer.transform(name, params, body, @context)

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

      assert result.bindings == expected
    end
  end

  describe "body" do
    test "single expression" do
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

    test "multiple expressions" do
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
end
