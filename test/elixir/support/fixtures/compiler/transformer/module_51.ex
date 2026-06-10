# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module51 do
  def test do
    for x <- [1, 2] do
      :expr
      x
    end
  end
end
