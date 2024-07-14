# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module56 do
  def test do
    for x <- [1, 2], reduce: 0 do
      acc when is_integer(x) when x > 1 when x < 9 -> acc + x
    end
  end
end
