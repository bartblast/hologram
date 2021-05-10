defmodule Hologram.Test.Fixtures.Compiler.Eliminator.Module6 do
  def action(:test_1, a, b) do
    Map.put(a, :key, b)
  end
end
