# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module26 do
  def test do
    &my_fun/2
  end

  def my_fun(x, y) do
    x * y + x
  end
end
