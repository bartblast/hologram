defmodule Hologram.Test.Fixtures.Compiler.ModuleTransformer.Module2 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.ModuleTransformer.Module1
    end
  end
end
