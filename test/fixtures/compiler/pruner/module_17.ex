defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module17 do
  use Hologram.Component

  def action(:test_1, _a, _b) do
    some_fun_1()
  end

  def some_fun_1 do
    some_fun_2()
  end

  def some_fun_2 do
    :ok
  end
end
