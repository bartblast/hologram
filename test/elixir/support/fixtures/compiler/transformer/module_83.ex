# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module83 do
  def test do
    my_fun(1, 2)
  end

  def my_fun(x, y) do
    x + y
  end
end
