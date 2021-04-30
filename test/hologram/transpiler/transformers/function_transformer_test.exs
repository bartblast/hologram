defmodule Hologram.Transpiler.FunctionTransformerTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{AtomType, Function, IntegerType, MapAccess, Variable}
  alias Hologram.Transpiler.FunctionTransformer

  test "arity" do
    # normalized AST from
    #
    # defmodule Abc do
    #   def test(1, 2, 3) do
    #     1
    #   end
    # end

    params = [1, 2, 3]
    result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

    assert %Function{} = result
    assert result.arity == 3
  end

  describe "bindings" do
    test "no bindings" do
      # normalized AST from
      #
      # defmodule Abc do
      #   def test(1, 2) do
      #     1
      #   end
      # end

      params = [1, 2]
      result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

      assert %Function{} = result
      assert result.bindings == []
    end

    test "single binding in single param" do
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
        [
          x: {1, [
            %MapAccess{
              key: %AtomType{value: :a}
            },
            %Variable{name: :x}
          ]}
        ]

      assert %Function{} = result
      assert result.bindings == expected
    end

    test "multiple bindings in single param" do
      # normalized AST from
      #
      # defmodule Abc do
      #   def test(1, %{a: x, b: y}) do
      #     1
      #   end
      # end

      params = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}, b: {:y, [line: 2], nil}]}]
      result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

      expected =
        [
          x: {1, [
            %MapAccess{
              key: %AtomType{value: :a}
            },
            %Variable{name: :x}
          ]},
          y: {1, [
            %MapAccess{
              key: %AtomType{value: :b}
            },
            %Variable{name: :y}
          ]}
        ]

      assert %Function{} = result
      assert result.bindings == expected
    end

    test "multiple bindings in multiple params" do
      # normalized AST from
      #
      # defmodule Abc do
      #   def test(1, %{a: k, b: m}, 2, %{c: s, d: t}) do
      #     1
      #   end
      # end

      params = [
        1,
        {:%{}, [line: 2], [a: {:k, [line: 2], nil}, b: {:m, [line: 2], nil}]},
        2,
        {:%{}, [line: 2], [c: {:s, [line: 2], nil}, d: {:t, [line: 2], nil}]},
      ]

      result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

      expected =
        [
          k: {1, [
            %MapAccess{
              key: %AtomType{value: :a}
            },
            %Variable{name: :k}
          ]},
          m: {1, [
            %MapAccess{
              key: %AtomType{value: :b}
            },
            %Variable{name: :m}
          ]},
          s: {3, [
            %MapAccess{
              key: %AtomType{value: :c}
            },
            %Variable{name: :s}
          ]},
          t: {3, [
            %MapAccess{
              key: %AtomType{value: :d}
            },
            %Variable{name: :t}
          ]}
        ]

      assert %Function{} = result
      assert result.bindings == expected
    end

    test "sorting" do
      # normalized AST from
      #
      # defmodule Abc do
      #   def test(y, z) do
      #     1
      #   end
      # end

      params = [{:y, [line: 2], nil}, {:x, [line: 2], nil}]
      result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

      expected =
      [
        x: {1, [
          %Variable{name: :x}
        ]},
        y: {0, [
          %Variable{name: :y}
        ]},
      ]

      assert %Function{} = result
      assert result.bindings == expected
    end
  end

  describe "body" do
    test "single expression" do
      # normalized AST from:
      #
      # def test do
      #   1
      # end

      result = FunctionTransformer.transform(:test, nil, [1], [:Test], [], [])
      expected = [%IntegerType{value: 1}]

      assert %Function{} = result
      assert result.body == expected
    end

    test "multiple expressions" do
      # normalized AST from:
      #
      # def test do
      #   1
      #   2
      # end

      result = FunctionTransformer.transform(:test, nil, [1, 2], [:Test], [], [])

      expected =
        [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ]

      assert %Function{} = result
      assert result.body == expected
    end
  end

  test "name" do
    # normalized AST from
    #
    # defmodule Abc do
    #   def test(1, 2) do
    #     1
    #   end
    # end

    result = FunctionTransformer.transform(:test, [1, 2], [1], [:Test], [], [])

    assert %Function{} = result
    assert result.name == :test
  end

  describe "params" do
    test "no params" do
      # normalized AST from:
      #
      # def test do
      #   1
      # end

      result = FunctionTransformer.transform(:test, nil, [1], [:Test], [], [])

      assert %Function{} = result
      assert result.params == []
    end

    test "var params" do
      # normalized AST from:
      #
      # def test(a, b) do
      #   1
      # end

      params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]
      result = FunctionTransformer.transform(:test, params, [1], [:Test], [], [])

      expected =
        [
          %Variable{name: :a},
          %Variable{name: :b}
        ]

      assert %Function{} = result
      assert result.params == expected
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

      expected =
        [
          %AtomType{value: :a},
          %IntegerType{value: 2}
        ]

      assert %Function{} = result
      assert result.params == expected
    end
  end
end
