defmodule Hologram.Compiler.MacroExpanderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.MacroDefinition
  alias Hologram.Compiler.MacroExpander

  @module Hologram.Test.Fixtures.Compiler.Expander.Module6

  describe "expand/2" do
    test "single expression / no params" do
      macro_def = %MacroDefinition{module: @module, name: :test_macro_1}

      result = MacroExpander.expand(macro_def, [])
      expected = [{:abc, [], @module}]

      assert result == expected
    end

    test "multiple expressions" do
      macro_def = %MacroDefinition{module: @module, name: :test_macro_2}

      result = MacroExpander.expand(macro_def, [])

      expected =
        [
          {:abc, [], @module},
          {:bcd, [], @module}
        ]

      assert result == expected
    end

    test "params / unquote calculated value" do
      macro_def = %MacroDefinition{module: @module, name: :test_macro_3}

      result = MacroExpander.expand(macro_def, [5, 6])
      expected = [11]

      assert result == expected
    end

    test "unquote param" do
      macro_def = %MacroDefinition{module: @module, name: :test_macro_4}

      result = MacroExpander.expand(macro_def, [5, 6])

      expected = [{:+, [context: @module, import: Kernel], [{:+, [context: @module, import: Kernel], [{:z, [], @module}, 5]}, 6]}]

      assert result == expected
    end

    test "__using__ macro" do
      macro_def = %MacroDefinition{module: @module, name: :__using__}

      result = MacroExpander.expand(macro_def, [nil])

      expected =
        [{:import, [context: @module],
          [
            {:__aliases__, [alias: false],
              [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module5]}
          ]}]

      assert result == expected
    end

    test "function definition, single expression" do
      macro_def = %MacroDefinition{module: @module, name: :test_macro_5}

      result = MacroExpander.expand(macro_def, [])

      expected =
        [{:def,
          [context: @module, import: Kernel],
          [
            {:test_function, [context: @module],
              @module},
            [do: {:__block__, [], [123]}]
          ]}]

      assert result == expected
    end

    test "function definition, multiple expressions" do
      macro_def = %MacroDefinition{module: @module, name: :test_macro_6}

      result = MacroExpander.expand(macro_def, [])

      expected =
        [{:def,
          [context: @module, import: Kernel],
          [
            {:test_function, [context: @module],
              @module},
            [do: {:__block__, [], [1, 2]}]
          ]}]

      assert result == expected
    end
  end

  test "expand/3" do
    result = MacroExpander.expand(@module, :test_macro_3, [5, 6])
    expected = [11]

    assert result == expected
  end
end
