defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module1 do
  import Hologram.Test.Fixtures.Compiler.Transformer.Module2

  defmacro macro_1a do
    quote do
      macro_2a()
    end
  end
end
