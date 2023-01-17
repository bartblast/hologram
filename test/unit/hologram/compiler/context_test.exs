defmodule Hologram.Compiler.ContextTest do
  use Hologram.Test.UnitCase, async: false
  alias Hologram.Compiler.Context

  test "put_functions/3" do
    context = %Context{
      functions: %{fun_1: %{1 => Module1, 2 => Module2}, fun_2: %{3 => Module3, 4 => Module4}}
    }

    added_functions = [fun_1: 1, fun_1: 3, fun_3: 5]
    result = Context.put_functions(context, Module5, added_functions)

    expected = %Context{
      functions: %{
        fun_1: %{1 => Module5, 2 => Module2, 3 => Module5},
        fun_2: %{3 => Module3, 4 => Module4},
        fun_3: %{5 => Module5}
      }
    }

    assert result == expected
  end
end
