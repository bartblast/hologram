# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module159 do
  def test(y) do
    with x when is_integer(x) and x > 5 <- y, do: nil
  end
end
