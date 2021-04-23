defmodule Hologram.Transpiler.FunctionTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, Function, IntegerType, MapAccess, MapType, Variable}
  alias Hologram.Transpiler.FunctionTransformer

  test "single expression" do
    # normalized AST from:
    #
    # def test do
    #   1
    # end

    result = FunctionTransformer.transform(:test, nil, [1], [:Test], [], [])

    expected = %Function{
      bindings: [],
      body: [
        %IntegerType{value: 1}
      ],
      name: :test,
      params: []
    }

    assert result == expected
  end

  test "multiple expressions" do
    # normalized AST from:
    #
    # def test do
    #   1
    #   2
    # end

    result = FunctionTransformer.transform(:test, nil, [1, 2], [:Test], [], [])

    expected = %Function{
      bindings: [],
      body: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ],
      name: :test,
      params: []
    }

    assert result == expected
  end

  test "no params" do
    # normalized AST from:
    #
    # def test do
    #   1
    # end

    result = FunctionTransformer.transform(:test, nil, [1], [:Test], [], [])

    expected = %Function{
      bindings: [],
      body: [
        %IntegerType{value: 1}
      ],
      name: :test,
      params: []
    }

    assert result == expected
  end

  test "var params" do
    # normalized AST from:
    #
    # def test(a, b) do
    #   1
    # end

    params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]
    result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

    expected = %Function{
      bindings: [
        [%Variable{name: :a}],
        [%Variable{name: :b}]
      ],
      body: [
        %IntegerType{value: 1}
      ],
      name: :test,
      params: [
        %Variable{name: :a},
        %Variable{name: :b}
      ]
    }

    assert result == expected
  end

  test "primitive type params" do
    # normalized AST from
    #
    # defmodule Abc do
    #   def test(:a, 2) do
    #     1
    #   end
    # end

    result = FunctionTransformer.transform(:test, [:a, 2], [1], [:Test], [], [])

    expected = %Function{
      bindings: [],
      body: [%IntegerType{value: 1}],
      name: :test,
      params: [
        %AtomType{value: :a},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end

  test "param bindings" do
    # normalized AST from
    #
    # defmodule Abc do
    #   def test(1, %{a: x}) do
    #     1
    #   end
    # end

    params = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}]}]
    result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

    expected =
      %Function{
        arity: nil,
        bindings: [
          [
            %Variable{name: :x},
            %MapAccess{
              key: %AtomType{value: :a}
            }
          ]
        ],
        body: [%IntegerType{value: 1}],
        name: :test,
        params: [
          %IntegerType{value: 1},
          %MapType{
            data: [
              {%AtomType{value: :a}, %Variable{name: :x}}
            ]
          }
        ]
      }

    assert result == expected
  end
end
