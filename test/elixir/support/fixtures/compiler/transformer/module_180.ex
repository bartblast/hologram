# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module180 do
  def test do
    for x <- [1, 2], <<3, 4>>, do: x
  end
end
