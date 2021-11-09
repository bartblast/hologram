defmodule Hologram.Compiler.HelpersTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, Helpers}

  alias Hologram.Compiler.IR.{
    AccessOperator,
    AtomType,
    FunctionDefinition,
    FunctionDefinitionVariants,
    IntegerType,
    ModuleDefinition,
    UseDirective,
    Variable
  }

  describe "aggregate_bindings/1" do
    test "no bindings" do
      # def test(1, 2) do
      # end

      params_ast = [1, 2]
      params = Helpers.transform_params(params_ast, %Context{})
      result = Helpers.aggregate_bindings(params)

      assert result == []
    end

    test "single binding in single param" do
      # def test(1, %{a: x}) do
      # end

      params_ast = [1, {:%{}, [line: 2], [a: {:x, [line: 2], nil}]}]
      params = Helpers.transform_params(params_ast, %Context{})
      result = Helpers.aggregate_bindings(params)

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
      params = Helpers.transform_params(params_ast, %Context{})
      result = Helpers.aggregate_bindings(params)

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

      params = Helpers.transform_params(params_ast, %Context{})
      result = Helpers.aggregate_bindings(params)

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
      params = Helpers.transform_params(params_ast, %Context{})
      result = Helpers.aggregate_bindings(params)

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

  describe "aggregate_function_def_variants/1" do
    test "single function with single variant" do
      function_defs = [
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]}
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test,
          params: [
            %Variable{name: :a}
          ]
        }
      ]

      result = Helpers.aggregate_function_def_variants(function_defs)

      expected = %{test: %FunctionDefinitionVariants{name: :test, variants: function_defs}}

      assert result == expected
    end

    test "single function with multiple variants" do
      function_def_1 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]}
        ],
        body: [
          %IntegerType{value: 1}
        ],
        name: :test,
        params: [
          %Variable{name: :a}
        ]
      }

      function_def_2 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]},
          b: {1, [%Variable{name: :b}]}
        ],
        body: [
          %IntegerType{value: 2}
        ],
        name: :test,
        params: [
          %Variable{name: :a},
          %Variable{name: :b}
        ]
      }

      function_defs = [function_def_1, function_def_2]
      result = Helpers.aggregate_function_def_variants(function_defs)

      expected = %{test: %FunctionDefinitionVariants{name: :test, variants: function_defs}}

      assert result == expected
    end

    test "multiple functions with single variant" do
      function_def_1 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]}
        ],
        body: [
          %IntegerType{value: 1}
        ],
        name: :test_1,
        params: [
          %Variable{name: :a}
        ]
      }

      function_def_2 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]}
        ],
        body: [
          %IntegerType{value: 2}
        ],
        name: :test_2,
        params: [
          %Variable{name: :a}
        ]
      }

      function_defs = [function_def_1, function_def_2]
      result = Helpers.aggregate_function_def_variants(function_defs)

      expected = %{
        test_1: %FunctionDefinitionVariants{name: :test_1, variants: [function_def_1]},
        test_2: %FunctionDefinitionVariants{name: :test_2, variants: [function_def_2]}
      }

      assert result == expected
    end

    test "multiple functions with multiple variants" do
      function_def_1 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]}
        ],
        body: [
          %IntegerType{value: 1}
        ],
        name: :test_1,
        params: [
          %Variable{name: :a}
        ]
      }

      function_def_2 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]},
          b: {1, [%Variable{name: :b}]}
        ],
        body: [
          %IntegerType{value: 2}
        ],
        name: :test_1,
        params: [
          %Variable{name: :a},
          %Variable{name: :b}
        ]
      }

      function_def_3 = %FunctionDefinition{
        bindings: [
          a: {0, [%Variable{name: :a}]}
        ],
        body: [
          %IntegerType{value: 3}
        ],
        name: :test_2,
        params: [
          %Variable{name: :a}
        ]
      }

      function_defs = [function_def_1, function_def_2, function_def_3]
      result = Helpers.aggregate_function_def_variants(function_defs)

      expected = %{
        test_1: %FunctionDefinitionVariants{
          name: :test_1,
          variants: [function_def_1, function_def_2]
        },
        test_2: %FunctionDefinitionVariants{name: :test_2, variants: [function_def_3]}
      }

      assert result == expected
    end
  end

  test "class_name/1" do
    assert Helpers.class_name(Abc.Bcd) == "Elixir_Abc_Bcd"
  end

  describe "fetch_block_body/1" do
    test "block" do
      ast = {:__block__, [], [1, 2]}
      result = Helpers.fetch_block_body(ast)

      assert result == [1, 2]
    end

    test "non-block" do
      ast = 1
      result = Helpers.fetch_block_body(ast)

      assert result == [1]
    end
  end

  test "get_components/1" do
    module_def_1 = %ModuleDefinition{
      module: Bcd.Cde,
      uses: [
        %UseDirective{module: Hologram.Component}
      ]
    }

    module_def_2 = %ModuleDefinition{
      module: Def.Efg,
      uses: [
        %UseDirective{module: Hologram.Component}
      ]
    }

    module_defs_map = %{
      Abc.Bcd => %ModuleDefinition{uses: []},
      Bcd.Cde => module_def_1,
      Cde.Def => %ModuleDefinition{uses: []},
      Def.Efg => module_def_2
    }

    result = Helpers.get_components(module_defs_map)
    expected = [module_def_1, module_def_2]

    assert result == expected
  end

  test "get_pages/1" do
    module_def_1 = %ModuleDefinition{
      module: Bcd.Cde,
      uses: [
        %UseDirective{module: Hologram.Page}
      ]
    }

    module_def_2 = %ModuleDefinition{
      module: Def.Efg,
      uses: [
        %UseDirective{module: Hologram.Page}
      ]
    }

    module_defs_map = %{
      Abc.Bcd => %ModuleDefinition{uses: []},
      Bcd.Cde => module_def_1,
      Cde.Def => %ModuleDefinition{uses: []},
      Def.Efg => module_def_2
    }

    result = Helpers.get_pages(module_defs_map)
    expected = [module_def_1, module_def_2]

    assert result == expected
  end

  test "module/1" do
    result = Helpers.module([:Hologram, :Compiler, :HelpersTest])
    expected = Elixir.Hologram.Compiler.HelpersTest
    assert result == expected
  end

  test "module_name/1" do
    assert Helpers.module_name(Abc.Bcd) == "Abc.Bcd"
  end

  describe "module_name_segments/1" do
    test "module" do
      assert Helpers.module_name_segments(Abc.Bcd) == [:Abc, :Bcd]
    end

    test "string" do
      assert Helpers.module_name_segments("Abc.Bcd") == [:Abc, :Bcd]
    end
  end

  describe "transform_params/2" do
    test "no params" do
      # def test do
      # end

      params = nil
      result = Helpers.transform_params(params, %Context{})

      assert result == []
    end

    test "vars" do
      # def test(a, b) do
      # end

      params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]
      result = Helpers.transform_params(params, %Context{})

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
      result = Helpers.transform_params(params, %Context{})

      expected = [
        %AtomType{value: :a},
        %IntegerType{value: 2}
      ]

      assert result == expected
    end
  end

  describe "uses_module?/2" do
    @used_module Hologram.Commons.Parser

    test "true" do
      user_module = %ModuleDefinition{
        uses: [
          %UseDirective{
            module: @used_module
          }
        ]
      }

      assert Helpers.uses_module?(user_module, @used_module)
    end

    test "false" do
      user_module = %ModuleDefinition{uses: []}
      refute Helpers.uses_module?(user_module, @used_module)
    end
  end
end
