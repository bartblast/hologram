defmodule Hologram.Compiler.Expander2Test do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Expander2

  describe "defmodule" do
    test "non-nested" do
      code = """
      defmodule Abc.Bcd do
        1
        2
      end
      """

      ast = ast(code)
      result = Expander2.expand(ast)

      expected =
        {:defmodule, [line: 1],
         [{:__aliases__, [line: 1], [:Abc, :Bcd]}, [do: {:__block__, [], [1, 2]}]]}

      assert result == expected
    end

    test "nested" do
      code = """
      defmodule Abc.Bcd do
        defmodule Cde.Def do
          2
          3
        end

        1
      end
      """

      ast = ast(code)
      result = Expander2.expand(ast)

      expected =
        {:defmodule, [line: 1],
         [
           {:__aliases__, [line: 1], [:Abc, :Bcd]},
           [
             do:
               {:__block__, [],
                [
                  {:defmodule, [line: 2],
                   [
                     {:__aliases__, [line: 2], [:Abc, :Bcd, :Cde, :Def]},
                     [do: {:__block__, [], [2, 3]}]
                   ]},
                  1
                ]}
           ]
         ]}
    end
  end
end
