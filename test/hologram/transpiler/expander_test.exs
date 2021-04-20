defmodule Hologram.Transpiler.ExpanderTest do
  use ExUnit.Case, async: true
  import Hologram.Transpiler.Parser, only: [parse!: 1]

  alias Hologram.Transpiler.Expander
  alias TestModule1
  alias TestModule2
  alias TestModule3
  alias TestModule5

  test "empty parent module" do
    code = """
    defmodule Test do
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [{:__aliases__, [line: 1], [:Test]}, [do: {:__block__, [], []}]]}

    assert result == expected
  end

  test "parent module with one expression which is not a use directive" do
    code = """
    defmodule Test do
      def test do
        1
      end
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [do: {:def, [line: 2], [{:test, [line: 2], nil}, [do: 1]]}]
      ]}

    assert result == expected
  end

  test "parent module with multiple expressions which are not use directives" do
    code = """
    defmodule Test do
      def test_1 do
        1
      end

      def test_2 do
        2
      end
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
          [
            {:def, [line: 2], [{:test_1, [line: 2], nil}, [do: 1]]},
            {:def, [line: 6], [{:test_2, [line: 6], nil}, [do: 2]]}
          ]}
        ]
      ]}

    assert result == expected
  end

  test "parent module with one use directive" do
    code = """
    defmodule Test do
      use TestModule2
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [do: {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]}]
      ]}

    assert result == expected
  end

  test "parent module with multiple use directives" do
    code = """
    defmodule Test do
      use TestModule2
      use TestModule4
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
          [
            {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]},
            {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule3]}]}
          ]}
        ]
      ]}

    assert result == expected
  end

  test "parent module with one use directive and one other expression" do
    code = """
    defmodule Test do
      use TestModule2

      def test do
        1
      end
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [
          do: {:__block__, [],
          [
            {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]},
            {:def, [line: 4], [{:test, [line: 4], nil}, [do: 1]]}
          ]}
        ]
      ]}

    assert result == expected
  end

  test "single quote at the root of __using__ macro with a single expression" do
    code = """
    defmodule Test do
      use TestModule2
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
      [
        {:__aliases__, [line: 1], [:Test]},
        [do: {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]}]
      ]}

    assert result == expected
  end

  test "single quote at the root of __using__ macro with multiple expressions" do
    code = """
    defmodule Test do
      use TestModule5
    end
    """

    result =
      parse!(code)
      |> Expander.expand()

    expected = {:defmodule, [line: 1],
    [
      {:__aliases__, [line: 1], [:Test]},
      [
        do: {:__block__, [],
         [
           {:import, [line: 4], [{:__aliases__, [line: 4], [:TestModule1]}]},
           {:import, [line: 5], [{:__aliases__, [line: 5], [:TestModule3]}]}
         ]}
      ]
    ]}

    assert result == expected
  end
end
