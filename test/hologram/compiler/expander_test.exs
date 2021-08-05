defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.Expander
  alias Hologram.Compiler.IR.MacroDefinition

  @module_2 Hologram.Test.Fixtures.Compiler.Expander.Module2
  @module_4 Hologram.Test.Fixtures.Compiler.Expander.Module4
  @module_5 Hologram.Test.Fixtures.Compiler.Expander.Module5
  @module_6 Hologram.Test.Fixtures.Compiler.Expander.Module6
  @module_segs_1 [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1]
  @module_segs_3 [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module3]

  describe "expand_macro/2" do
    test "single expression / no params" do
      macro_def = %MacroDefinition{module: @module_6, name: :test_macro_1}

      result = Expander.expand_macro(macro_def, [])
      expected = [{:abc, [], @module_6}]

      assert result == expected
    end

    test "multiple expressions" do
      macro_def = %MacroDefinition{module: @module_6, name: :test_macro_2}

      result = Expander.expand_macro(macro_def, [])

      expected =
        [
          {:abc, [], @module_6},
          {:bcd, [], @module_6}
        ]

      assert result == expected
    end

    test "params / unquote calculated value" do
      macro_def = %MacroDefinition{module: @module_6, name: :test_macro_3}

      result = Expander.expand_macro(macro_def, [5, 6])
      expected = [11]

      assert result == expected
    end

    test "unquote param" do
      macro_def = %MacroDefinition{module: @module_6, name: :test_macro_4}

      result = Expander.expand_macro(macro_def, [5, 6])

      expected = [{:+, [context: @module_6, import: Kernel], [{:+, [context: @module_6, import: Kernel], [{:z, [], @module_6}, 5]}, 6]}]

      assert result == expected
    end

    test "__using__ macro" do
      macro_def = %MacroDefinition{module: @module_6, name: :__using__}

      result = Expander.expand_macro(macro_def, [nil])

      expected =
        [{:import, [context: @module_6],
          [
            {:__aliases__, [alias: false],
              [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module5]}
          ]}]

      assert result == expected
    end

    test "function definition, single expression" do
      macro_def = %MacroDefinition{module: @module_6, name: :test_macro_5}

      result = Expander.expand_macro(macro_def, [])

      expected =
        [{:def,
          [context: @module_6, import: Kernel],
          [
            {:test_function, [context: @module_6],
              @module_6},
            [do: {:__block__, [], [123]}]
          ]}]

      assert result == expected
    end

    test "function definition, multiple expressions" do
      macro_def = %MacroDefinition{module: @module_6, name: :test_macro_6}

      result = Expander.expand_macro(macro_def, [])

      expected =
        [{:def,
          [context: @module_6, import: Kernel],
          [
            {:test_function, [context: @module_6],
              @module_6},
            [do: {:__block__, [], [1, 2]}]
          ]}]

      assert result == expected
    end
  end

  test "expand_macro/3" do
    result = Expander.expand_macro(@module_6, :test_macro_3, [5, 6])
    expected = [11]

    assert result == expected
  end

  describe "expand_use_directives/1" do
    test "no use directives / non-expandable expressions only" do
      code = """
      defmodule Test do
        1
        2
      end
      """

      ast = ast(code)
      result = Expander.expand_use_directives(ast)

      assert result == ast
    end

    test "single use directive" do
      code = """
      defmodule Test do
        use Hologram.Test.Fixtures.Compiler.Expander.Module2
      end
      """

      ast = ast(code)

      result = Expander.expand_use_directives(ast)

      expected =
        {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
            [
              {:import, [context: @module_2],
                [
                  {:__aliases__, [alias: false], @module_segs_1}
                ]}
            ]}
          ]
        ]}

      assert result == expected
    end

    test "multiple use directives" do
      code = """
      defmodule Test do
        use Hologram.Test.Fixtures.Compiler.Expander.Module2
        use Hologram.Test.Fixtures.Compiler.Expander.Module4
      end
      """

      ast = ast(code)

      result = Expander.expand_use_directives(ast)

      expected =
        {:defmodule, [line: 1],
          [
            {:__aliases__, [line: 1], [:Test]},
            [
              do: {:__block__, [],
                [
                  {:import, [context: @module_2],
                  [
                    {:__aliases__, [alias: false], @module_segs_1}
                  ]},
                  {:import, [context: @module_4],
                  [
                    {:__aliases__, [alias: false], @module_segs_3}
                  ]}
                ]}
            ]
          ]}

      assert result == expected
    end

    test "multiple expressions expanded" do
      code = """
      defmodule Test do
        use Hologram.Test.Fixtures.Compiler.Expander.Module5
      end
      """

      ast = ast(code)

      result = Expander.expand_use_directives(ast)

      expected =
        {:defmodule, [line: 1],
          [
            {:__aliases__, [line: 1], [:Test]},
            [
              do: {:__block__, [],
                [
                  {:import, [context: @module_5],
                  [
                    {:__aliases__, [alias: false], @module_segs_1}
                  ]},
                  {:import, [context: @module_5],
                  [
                    {:__aliases__, [alias: false], @module_segs_3}
                  ]}
                ]}
            ]
          ]}

      assert result == expected
    end
  end
end
