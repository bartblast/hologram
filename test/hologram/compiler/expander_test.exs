defmodule Hologram.Compiler.ExpanderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Expander

  @module_1 [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module1]
  @module_3 [:Hologram, :Test, :Fixtures, :Compiler, :Expander, :Module3]

  test "no use directives" do
    code = """
    defmodule Test do
      def test do
          1
      end
    end
    """

    ast = ast(code)
    result = Expander.expand(ast)

    assert result == ast
  end

  test "single use directive" do
    code = """
    defmodule Test do
      use Hologram.Test.Fixtures.Compiler.Expander.Module2
    end
    """

    ast = ast(code)

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
       [
         {:__aliases__, [line: 1], [:Test]},
         [
           do: {:__block__, [], [{:import, [line: 4], [{:__aliases__, [line: 4], @module_1}]}]}
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

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
       [
         {:__aliases__, [line: 1], [:Test]},
         [
           do:
             {:__block__, [],
              [
                {:import, [line: 4], [{:__aliases__, [line: 4], @module_1}]},
                {:import, [line: 4], [{:__aliases__, [line: 4], @module_3}]}
              ]}
         ]
       ]}

    assert result == expected
  end

  test "single quote at the root of __using__ macro with a single expression" do
    code = """
    defmodule Test do
      use Hologram.Test.Fixtures.Compiler.Expander.Module2
    end
    """

    ast = ast(code)

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
       [
         {:__aliases__, [line: 1], [:Test]},
         [
           do: {:__block__, [], [{:import, [line: 4], [{:__aliases__, [line: 4], @module_1}]}]}
         ]
       ]}

    assert result == expected
  end

  test "single quote at the root of __using__ macro with multiple expressions" do
    code = """
    defmodule Test do
      use Hologram.Test.Fixtures.Compiler.Expander.Module5
    end
    """

    ast = ast(code)

    result = Expander.expand(ast)

    expected =
      {:defmodule, [line: 1],
       [
         {:__aliases__, [line: 1], [:Test]},
         [
           do:
             {:__block__, [],
              [
                {:import, [line: 4], [{:__aliases__, [line: 4], @module_1}]},
                {:import, [line: 5], [{:__aliases__, [line: 5], @module_3}]}
              ]}
         ]
       ]}

    assert result == expected
  end
end
