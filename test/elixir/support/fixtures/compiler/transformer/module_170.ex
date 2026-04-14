# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module170 do
  def test(y) do
    with s when is_binary(s) <- y do
    end
  end
end
