# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.IR.Module1 do
  def my_fun_1(x, y) do
    x + y
  end

  def my_fun_2, do: &my_fun_1/2
end
