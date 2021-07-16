defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module14 do
  use Hologram.Component

  def action(:test_1, _a, _b) do
    some_fun()
  end

  def some_fun do
    :ok
  end
end
