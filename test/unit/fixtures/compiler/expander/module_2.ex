defmodule Hologram.Test.Fixtures.Compiler.Expander.Module2 do
  defmacro macro_2a do
    quote do
      123
    end
  end

  defmacro macro_2b do
    quote do
      100
      200
    end
  end
end
