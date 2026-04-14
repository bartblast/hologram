# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module159 do
  def test(x) do
    with i when is_integer(i) and x > 5 <- x, do: x
  end
end
