defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module1 do
  def action(:test_1, _a, _b) do
    :ok
  end

  def action(:test_2, _a, _b, _c) do
    :ok
  end
end
