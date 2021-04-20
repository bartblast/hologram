# TODO: refactor

defmodule Hologram.Transpiler.TransformerTest do
  use ExUnit.Case, async: true

  import Hologram.Transpiler.Parser, only: [parse!: 1]

  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Transpiler.AST.{ListType, MapType, StructType}
  alias Hologram.Transpiler.AST.MatchOperator
  alias Hologram.Transpiler.AST.MapAccess
  alias Hologram.Transpiler.AST.{Alias, Call, Function, Import, Module, ModuleAttribute, Variable}
  alias Hologram.Transpiler.Transformer
  alias TestModule1
  alias TestModule4

  describe "primitive types" do
    test "atom" do
      ast = parse!(":test")
      assert Transformer.transform(ast) == %AtomType{value: :test}
    end

    test "boolean" do
      ast = parse!("true")
      assert Transformer.transform(ast) == %BooleanType{value: true}
    end

    test "integer" do
      ast = parse!("1")
      assert Transformer.transform(ast) == %IntegerType{value: 1}
    end

    test "string" do
      ast = parse!("\"test\"")
      assert Transformer.transform(ast) == %StringType{value: "test"}
    end
  end

  describe "data structures" do
    test "map, empty" do
      result =
        parse!("%{}")
        |> Transformer.transform()

      expected = %MapType{data: []}

      assert result == expected
    end

    test "map, not nested" do
      result =
        parse!("%{a: 1, b: 2}")
        |> Transformer.transform()

      expected = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b}, %IntegerType{value: 2}}
        ]
      }

      assert result == expected
    end

    test "map, nested" do
      result =
        parse!("%{a: 1, b: %{c: 2, d: %{e: 3, f: 4}}}")
        |> Transformer.transform()

      expected = %MapType{
        data: [
          {%AtomType{value: :a}, %IntegerType{value: 1}},
          {%AtomType{value: :b},
           %MapType{
             data: [
               {%AtomType{value: :c}, %IntegerType{value: 2}},
               {%AtomType{value: :d},
                %MapType{
                  data: [
                    {%AtomType{value: :e}, %IntegerType{value: 3}},
                    {%AtomType{value: :f}, %IntegerType{value: 4}}
                  ]
                }}
             ]
           }}
        ]
      }

      assert result == expected
    end
  end

  describe "operators" do
    test "match operator, simple" do
      result =
        parse!("x = 1")
        |> Transformer.transform()

      expected = %MatchOperator{
        bindings: [[%Variable{name: :x}]],
        left: %Variable{name: :x},
        right: %IntegerType{value: 1}
      }

      assert result == expected
    end

    # TODO: test different kinds of bindings (map, list, etc.)

    test "match operator, map, not nested" do
      result =
        parse!("%{a: x, b: y} = %{a: 1, b: 2}")
        |> Transformer.transform()

      expected = %MatchOperator{
        bindings: [
          [
            %Variable{name: :x},
            %MapAccess{key: %AtomType{value: :a}}
          ],
          [
            %Variable{name: :y},
            %MapAccess{key: %AtomType{value: :b}}
          ]
        ],
        left: %MapType{
          data: [
            {%AtomType{value: :a}, %Variable{name: :x}},
            {%AtomType{value: :b}, %Variable{name: :y}}
          ]
        },
        right: %MapType{
          data: [
            {%AtomType{value: :a}, %IntegerType{value: 1}},
            {%AtomType{value: :b}, %IntegerType{value: 2}}
          ]
        }
      }

      assert result == expected
    end

    test "match operator, map, nested" do
      code =
        "%{a: 1, b: %{p: x, r: 4}, c: 3, d: %{m: 0, n: y}} = %{a: 1, b: %{p: 9, r: 4}, c: 3, d: %{m: 0, n: 8}}"

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %MatchOperator{
        bindings: [
          [
            %Variable{name: :x},
            %MapAccess{key: %AtomType{value: :b}},
            %MapAccess{key: %AtomType{value: :p}}
          ],
          [
            %Variable{name: :y},
            %MapAccess{key: %AtomType{value: :d}},
            %MapAccess{key: %AtomType{value: :n}}
          ]
        ],
        left: %MapType{
          data: [
            {%AtomType{value: :a}, %IntegerType{value: 1}},
            {
              %AtomType{value: :b},
              %MapType{
                data: [
                  {%AtomType{value: :p}, %Variable{name: :x}},
                  {%AtomType{value: :r}, %IntegerType{value: 4}}
                ]
              }
            },
            {%AtomType{value: :c}, %IntegerType{value: 3}},
            {%AtomType{value: :d},
             %MapType{
               data: [
                 {%AtomType{value: :m}, %IntegerType{value: 0}},
                 {%AtomType{value: :n}, %Variable{name: :y}}
               ]
             }}
          ]
        },
        right: %MapType{
          data: [
            {%AtomType{value: :a}, %IntegerType{value: 1}},
            {%AtomType{value: :b},
             %MapType{
               data: [
                 {%AtomType{value: :p}, %IntegerType{value: 9}},
                 {%AtomType{value: :r}, %IntegerType{value: 4}}
               ]
             }},
            {%AtomType{value: :c}, %IntegerType{value: 3}},
            {%AtomType{value: :d},
             %MapType{
               data: [
                 {%AtomType{value: :m}, %IntegerType{value: 0}},
                 {%AtomType{value: :n}, %IntegerType{value: 8}}
               ]
             }}
          ]
        }
      }

      assert result == expected
    end
  end

  describe "other" do
    test "import" do
      result =
        parse!("import Prefix.Test")
        |> Transformer.transform()

      expected = %Import{module: [:Prefix, :Test]}

      assert result == expected
    end

    test "alias" do
      result =
        parse!("alias Prefix.Test")
        |> Transformer.transform()

      expected = %Alias{module: [:Prefix, :Test]}

      assert result == expected
    end

    test "function call on the current module" do
      code = """
      defmodule Abc.Bce do
        def test_1(a, b) do
          1
          test_2(c, d)
          3
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)
        |> hd()
        |> Map.get(:body)
        |> Enum.at(1)

      expected = %Call{
        function: :test_2,
        module: [:Abc, :Bce],
        params: [
          %Variable{name: :c},
          %Variable{name: :d}
        ]
      }

      assert result == expected
    end

    test "function call on another module" do
      code = """
      defmodule Abc.Bce do
        def test_1(a, b) do
          1
          Cde.Def.test_2(c, d)
          3
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)
        |> hd()
        |> Map.get(:body)
        |> Enum.at(1)

      expected = %Call{
        function: :test_2,
        module: [:Cde, :Def],
        params: [
          %Variable{name: :c},
          %Variable{name: :d}
        ]
      }

      assert result == expected
    end

    test "function call on aliased module" do
      code = """
      defmodule Abc.Bce do
        alias Cde.Def.Efg

        def test_1(a, b) do
          1
          Efg.test_2(c, d)
          3
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)
        |> hd()
        |> Map.get(:body)
        |> Enum.at(1)

      expected = %Call{
        function: :test_2,
        module: [:Cde, :Def, :Efg],
        params: [
          %Variable{name: :c},
          %Variable{name: :d}
        ]
      }

      assert result == expected
    end

    # TODO: test function with 1 param only

    test "function definition, no params, single expression" do
      code = """
        def test do
          1
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

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

    test "function definition, multiple params, single expression" do
      code = """
        def test(a, b) do
          1
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

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

    test "function definition, multiple params, multiple expressions" do
      code = """
        def test(a, b) do
          1
          2
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %Function{
        bindings: [
          [%Variable{name: :a}],
          [%Variable{name: :b}]
        ],
        body: [
          %IntegerType{value: 1},
          %IntegerType{value: 2}
        ],
        name: :test,
        params: [
          %Variable{name: :a},
          %Variable{name: :b}
        ]
      }

      assert result == expected
    end

    test "function definition, vars in params" do
      code = """
      defmodule Abc do
        def test(a, b) do
          1
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)
        |> hd()

      expected = %Function{
        bindings: [
          [%Variable{name: :a}],
          [%Variable{name: :b}]
        ],
        body: [%IntegerType{value: 1}],
        name: :test,
        params: [
          %Variable{name: :a},
          %Variable{name: :b}
        ]
      }

      assert result == expected
    end

    test "function definition, non-vars in params" do
      code = """
      defmodule Abc do
        def test(:a, 2) do
          1
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)
        |> hd()

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

    test "function definition, vars and non-vars in params" do
      code = """
      defmodule Abc do
        def test(:a, x) do
          1
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)
        |> hd()

      expected = %Function{
        bindings: [
          [%Variable{name: :x}]
        ],
        body: [%IntegerType{value: 1}],
        name: :test,
        params: [
          %AtomType{value: :a},
          %Variable{name: :x}
        ]
      }

      assert result == expected
    end

    test "eliminated functions" do
      code = """
      defmodule Abc do
        def render(a) do
          1
        end

        def test(b) do
          2
        end

        def render(c, d) do
          3
        end
      end
      """

      result =
        parse!(code)
        |> Transformer.transform()
        |> Map.get(:functions)

      expected = [
        %Function{
          bindings: [[%Variable{name: :b}]],
          body: [%IntegerType{value: 2}],
          name: :test,
          params: [%Variable{name: :b}]
        },
        %Function{
          bindings: [[%Variable{name: :c}], [%Variable{name: :d}]],
          body: [%IntegerType{value: 3}],
          name: :render,
          params: [%Variable{name: :c}, %Variable{name: :d}]
        }
      ]

      assert result == expected
    end

    test "module without directives" do
      code = """
        defmodule Prefix.Test do
          def test(a) do
            1
          end

          :not_a_function

          def test(a, b) do
            1
            2
          end
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %Module{
        aliases: %{list: [], map: %{}},
        functions: [
          %Function{
            bindings: [
              [%Variable{name: :a}]
            ],
            body: [
              %IntegerType{value: 1}
            ],
            name: :test,
            params: [
              %Variable{name: :a}
            ]
          },
          %Function{
            bindings: [
              [%Variable{name: :a}],
              [%Variable{name: :b}]
            ],
            body: [
              %IntegerType{value: 1},
              %IntegerType{value: 2}
            ],
            name: :test,
            params: [
              %Variable{name: :a},
              %Variable{name: :b}
            ]
          }
        ],
        imports: [],
        name: [:Prefix, :Test]
      }

      assert result == expected
    end

    # TODO: test single and multiple aliases cases
    test "module with aliases" do
      code = """
        defmodule Prefix.Test do
          alias Abc.Bcd
          alias Cde.Efg

          def test(a) do
            1
          end

          :not_a_function

          def test(a, b) do
            1
            2
          end
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %Module{
        aliases: %{
          list: [
            %Alias{module: [:Abc, :Bcd]},
            %Alias{module: [:Cde, :Efg]}
          ],
          map: %{
            Bcd: [:Abc, :Bcd],
            Efg: [:Cde, :Efg]
          }
        },
        functions: [
          %Function{
            bindings: [
              [%Variable{name: :a}]
            ],
            body: [
              %IntegerType{value: 1}
            ],
            name: :test,
            params: [
              %Variable{name: :a}
            ]
          },
          %Function{
            bindings: [
              [%Variable{name: :a}],
              [%Variable{name: :b}]
            ],
            body: [
              %IntegerType{value: 1},
              %IntegerType{value: 2}
            ],
            name: :test,
            params: [
              %Variable{name: :a},
              %Variable{name: :b}
            ]
          }
        ],
        imports: [],
        name: [:Prefix, :Test]
      }

      assert result == expected
    end

    test "module with single use directive" do
      code = """
        defmodule Prefix.Test do
          use TestModule2
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %Module{
        aliases: %{list: [], map: %{}},
        functions: [],
        imports: [%Import{module: [:TestModule1]}],
        name: [:Prefix, :Test]
      }

      assert result == expected
    end

    test "module with multiple use directives" do
      code = """
        defmodule Prefix.Test do
          use TestModule2
          use TestModule4
        end
      """

      result =
        parse!(code)
        |> Transformer.transform()

      expected = %Module{
        aliases: %{list: [], map: %{}},
        functions: [],
        imports: [
          %Import{module: [:TestModule1]},
          %Import{module: [:TestModule3]}
        ],
        name: [:Prefix, :Test]
      }

      assert result == expected
    end

    # TODO: test structs with namespace which have aliases, e.g. alias Abc.Bcd -> %Bcd.Cde{} (not implemented yet)

    test "struct, without namespace, not aliased" do
      result =
        parse!("%TestStruct{abc: 1}")
        |> Transformer.transform()

      expected = %StructType{
        data: [
          {%AtomType{value: :abc}, %IntegerType{value: 1}}
        ],
        module: [:TestStruct]
      }

      assert result == expected
    end

    test "struct, without namespace, aliased" do
      code = "%TestStruct{abc: 1}"

      aliases = %{
        OtherStruct: [:Abc, :Bcd, :OtherStruct],
        TestStruct: [:Cde, :Def, :TestStruct]
      }

      result =
        parse!(code)
        |> Transformer.transform(nil, aliases)

      expected = %StructType{
        data: [
          {%AtomType{value: :abc}, %IntegerType{value: 1}}
        ],
        module: [:Cde, :Def, :TestStruct]
      }

      assert result == expected
    end

    test "variable" do
      ast = parse!("x")
      assert Transformer.transform(ast) == %Variable{name: :x}
    end

    test "module attribute" do
      ast = parse!("@x")
      assert Transformer.transform(ast) == %ModuleAttribute{name: :x}
    end
  end
end
