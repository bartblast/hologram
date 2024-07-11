# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module30 do
  def test(my_module) do
    &my_module.my_fun/2
  end

  def my_fun(x, y) do
    x * y + x
  end
end
