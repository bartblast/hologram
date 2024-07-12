# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module41 do
  def test do
    for x <- [1, 2], y <- [3, 4], do: x * y
  end
end
