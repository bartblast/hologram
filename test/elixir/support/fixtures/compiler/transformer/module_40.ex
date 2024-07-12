# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module40 do
  def test do
    for x <- [1, 2], do: x * x
  end
end
