# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module50 do
  def test do
    for x <- [1, 2], do: x
  end
end
