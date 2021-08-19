defmodule Hologram.Test.Fixtures.Compiler.Reflection.Module2 do
  defmacro test_macro(a) do
    quote do unquote(a) end
  end

  defmacro test_macro(a, b) do
    quote do unquote(a) + unquote(b) end
  end

  defmacro test_macro(a, b, c) do
    quote do unquote(a) + unquote(b) + unquote(c) end
  end
end
