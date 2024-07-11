# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module31 do
  def test do
    &my_fun(&1, 2, [3, &2])
  end

  def my_fun(a, b, c) do
    [a] ++ [b] ++ c
  end
end
