# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module160 do
  def test(x, y) do
    with i when is_integer(i) <- x,
         s when is_binary(s) <- y do
      :ok
    end
  end
end
