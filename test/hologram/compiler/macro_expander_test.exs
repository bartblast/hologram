defmodule Hologram.Compiler.MacroExpanderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.MacroDefinition
  alias Hologram.Compiler.MacroExpander

  @module Hologram.Test.Fixtures.Compiler.Expander.Module6

  test "single expression / no params" do
    macro_def = %MacroDefinition{module: @module, name: :test_macro_1}

    result = MacroExpander.expand(macro_def, [])
    expected = {:abc, [], @module}

    assert result == expected
  end

  test "multiple expressions" do
    macro_def = %MacroDefinition{module: @module, name: :test_macro_2}

    result = MacroExpander.expand(macro_def, [])

    expected =
      {:__block__, [], [
        {:abc, [], @module},
        {:bcd, [], @module}
      ]}

    assert result == expected
  end

  test "params / unquote calculated value" do
    macro_def = %MacroDefinition{module: @module, name: :test_macro_3}

    result = MacroExpander.expand(macro_def, [5, 6])
    expected = 11

    assert result == expected
  end

  test "unquote param" do
    macro_def = %MacroDefinition{module: @module, name: :test_macro_4}

    result = MacroExpander.expand(macro_def, [5, 6])

    context = [context: @module, import: Kernel]
    expected = {:+, context, [{:+, context, [{:z, [], @module}, 5]}, 6]}

    assert result == expected
  end

  test "__using__ macro" do
    macro_def = %MacroDefinition{module: @module, name: :__using__}

    result = MacroExpander.expand(macro_def, [nil])

    expected =
      {:import, [context: @module],
        [
          {:__aliases__, [alias: false],
            [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module5]}
        ]}

    assert result == expected
  end
end
