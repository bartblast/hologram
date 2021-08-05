defmodule Hologram.Compiler.MacrosExpanderTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.MacrosExpander
  alias Hologram.Compiler.IR.RequireDirective

  @module_6 Hologram.Test.Fixtures.Compiler.Expander.Module6
  @requires [%RequireDirective{module: Hologram.Test.Fixtures.Compiler.Expander.Module6}]

  test "no macros / non-expandable expressions only" do
    code = """
    defmodule Test do
      1
      2
    end
    """

    ast = ast(code)
    result = MacrosExpander.expand(ast, @requires)

    assert result == ast
  end

  test "single macro" do
    code = """
    defmodule Test do
      test_macro_1
    end
    """

    ast = ast(code)

    result = MacrosExpander.expand(ast, @requires)

    expected =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [{:abc, [], @module_6}]}
          ]
        ]}


    assert result == expected
  end

  test "multiple macros" do
    code = """
    defmodule Test do
      test_macro_1
      test_macro_7
    end
    """

    ast = ast(code)

    result = MacrosExpander.expand(ast, @requires)

    expected =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [{:abc, [], @module_6}, 777]}
          ]
        ]}

    assert result == expected
  end

  test "multiple expressions expanded" do
    code = """
    defmodule Test do
      test_macro_2
    end
    """

    ast = ast(code)

    result = MacrosExpander.expand(ast, @requires)

    expected =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [
                {:abc, [], @module_6},
                {:bcd, [], @module_6}
              ]}
          ]
        ]}

    assert result == expected
  end

  test "macro with params" do
    code = """
    defmodule Test do
      test_macro_4(1, 2)
    end
    """

    ast = ast(code)

    result = MacrosExpander.expand(ast, @requires)

    expected =
      {:defmodule, [line: 1],
        [
          {:__aliases__, [line: 1], [:Test]},
          [
            do: {:__block__, [],
              [
                {:+, [context: @module_6, import: Kernel],
                [
                  {:+,
                    [context: @module_6, import: Kernel], [
                      {:z, [], @module_6},
                      1
                    ]
                  },
                  2
                ]}
              ]}
          ]
        ]}

    assert result == expected
  end
end
