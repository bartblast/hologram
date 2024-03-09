# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module8 do
  def fun_1(x), do: x

  def fun_1(x, y), do: {x, y}

  def fun_2(:a), do: 1

  def fun_2(:b), do: 2

  def fun_2(:a, :b), do: 3

  def fun_2(:b, :c), do: 4

  def fun_2(:a, :b, :c), do: 5

  def fun_2(:b, :c, :d), do: 6

  def fun_3(x), do: x

  def fun_3(x, y), do: {x, y}
end
