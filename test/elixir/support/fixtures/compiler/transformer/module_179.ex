# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module179 do
  def test do
    for x <- [1, 2], x > 1, <<(y <- <<3, 4>>)>>, do: x * y
  end
end
