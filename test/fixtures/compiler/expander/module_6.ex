defmodule Hologram.Test.Fixtures.Compiler.Expander.Module6 do
  defmacro test_macro_1 do
    quote do
      abc
    end
  end

  defmacro test_macro_2 do
    quote do
      abc
      bcd
    end
  end

  defmacro test_macro_3(a, b) do
    result = a + b

    quote do
      unquote(result)
    end
  end

  defmacro test_macro_4(x, y) do
    quote do
      z + unquote(x) + unquote(y)
    end
  end

  defmacro test_macro_5 do
    quote do
      def test_function, do: 123
    end
  end

  defmacro test_macro_6 do
    quote do
      def test_function do
        1
        2
      end
    end
  end

  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.Expander.Module5
    end
  end
end
