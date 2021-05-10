defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module2 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module1
    end
  end
end
