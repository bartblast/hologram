defmodule Hologram.Test.Fixtures.Compiler.Expander.Module4 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.Expander.Module3
    end
  end
end
