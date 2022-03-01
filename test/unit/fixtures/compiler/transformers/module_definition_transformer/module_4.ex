defmodule Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module4 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.ModuleDefinitionTransformer.Module3
    end
  end
end
