defmodule Hologram.Test.Fixtures.Compiler.Processor.Module17 do
  defmacro macro_1 do
    quote do 1 end
  end

  defmacro macro_2(a) do
    quote do unquote(a) end
  end

  defmacro macro_2(a, b) do
    quote do unquote(a) + unquote(b) end
  end

  defmacro macro_2(a, b, c) do
    quote do unquote(a) + unquote(b) + unquote(c) end
  end

  defmacro macro_3 do
    quote do 3 end
  end

  def fun_1 do
    1
  end
end
