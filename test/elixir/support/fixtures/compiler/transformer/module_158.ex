# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module158 do
  def test(x) do
    with i when is_integer(i) <- x, do: x
  end
end
