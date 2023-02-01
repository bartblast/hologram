defmodule Hologram.Test.Fixtures.Compiler.Expander.Module3 do
  import Hologram.Test.Fixtures.Compiler.Expander.Module2

  defmacro macro_3a do
    quote do
      macro_2a()
    end
  end

  defmacro macro_3b do
    quote do
      macro_2a
    end
  end

  defmacro macro_3c do
    quote do
      macro_2b()
      300
    end
  end
end
