defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module22 do
  use Hologram.Page

  def action(:test_1, _a, _b) do
    Map.put(%{}, :x, 9)
  end
end
