defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Expander

  @module_2 Hologram.Test.Fixtures.Compiler.Expander.Module2
  @module_4 Hologram.Test.Fixtures.Compiler.Expander.Module4
  @module_5 Hologram.Test.Fixtures.Compiler.Expander.Module5
  @module_segs_1 [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1]
  @module_segs_3 [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module3]

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
