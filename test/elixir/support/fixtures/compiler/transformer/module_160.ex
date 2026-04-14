# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module160 do
  def test(x, y) do
    with s when is_binary(s) <- x,
         i when is_integer(i) <- y do
      {s, i}
    end
  end
end
