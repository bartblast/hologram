defmodule Hologram.Test.Fixtures.ModuleTransformer.Module2 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.ModuleTransformer.Module1
    end
  end
end
