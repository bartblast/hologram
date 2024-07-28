# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module110 do
  def test do
    try do
      x = 1
      x
    rescue
      e -> e
    end
  end
end
