# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module154 do
  def test do
    &my_fun/1
  end

  def my_fun(x) do
    x * x
  end
end
