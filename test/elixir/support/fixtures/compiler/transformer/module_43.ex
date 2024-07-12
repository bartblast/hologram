# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module43 do
  def test do
    for x when is_integer(x) <- [1, 2], do: x * x
  end
end
