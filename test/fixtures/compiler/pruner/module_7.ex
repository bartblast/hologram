defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module7 do
  use Hologram.Page

  def action(:test_1, a, b) do
    some_fun()
  end

  def some_fun do
    :ok
  end
end
