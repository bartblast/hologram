defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module2 do
  use Hologram.Page

  def action(:test_1, a, b) do
    :ok
  end

  def action(:test_2, a, b, c) do
    :ok
  end
end
