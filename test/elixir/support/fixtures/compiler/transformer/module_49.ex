# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module49 do
  def test do
    for x <- [1, 2], uniq: true, do: x * x
  end
end
