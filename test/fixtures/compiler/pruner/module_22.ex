defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module22 do
  use Hologram.Page

  def action(:test_1, a, b) do
    Map.put(%{}, :x, 9)
  end
end
