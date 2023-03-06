defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  import Hologram.Test.Fixtures.Compiler.Transformer.Module2
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2, as: MyAlias

  defmacro macro_1a do
    quote do
      macro_2a()
    end
  end

  defmacro macro_1b do
    quote do
      macro_2a
    end
  end

  defmacro macro_1c do
    quote do
      MyAlias.macro_2a()
    end
  end

  defmacro macro_1d do
    quote do
      my_fun()
    end
  end

  defmacro macro_1e do
    quote do
      my_fun(1, 2)
    end
  end
end
