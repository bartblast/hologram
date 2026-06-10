# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module177 do
  def test do
    for <<(x <- <<1, 2>>)>>, do: x
  end
end
