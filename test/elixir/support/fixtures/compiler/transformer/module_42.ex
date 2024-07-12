# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module42 do
  def test do
    for {x, y} <- [{1, 2}, {3, 4}], do: x * y
  end
end
