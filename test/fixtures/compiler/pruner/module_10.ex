defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module10 do
  use Hologram.Page

  def action(:test_1, a, b) do
    some_fun_1()
  end

  def some_fun_1 do
    some_fun_2()
  end

  def some_fun_2 do
    :ok
  end
end
