# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module45 do
  def test do
    for x when is_integer(x) when x > 1 when x < 9 <- [1, 2], do: x * x
  end
end
