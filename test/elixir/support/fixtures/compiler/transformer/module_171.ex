# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module171 do
  def test(y) do
    key = :ok

    with ^key <- y do
    end
  end
end
