# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module176 do
  def test do
    for x <- [1, 2], my_filter(x), y <- [3, 4], do: x * y
  end

  defp my_filter(x) do
    x + 1
  end
end
