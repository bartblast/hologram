defmodule Hologram.Test.Fixtures.Compiler.Expander.Module2 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.Expander.Module1
    end
  end
end
