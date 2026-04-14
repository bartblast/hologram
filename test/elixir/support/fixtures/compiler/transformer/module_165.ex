# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module165 do
  def test(y) do
    with x <- y do
      a = x
      a
    end
  end
end
