# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module46 do
  def test do
    for x <- [1, 2], my_filter(x), do: x * x
  end

  defp my_filter(x) do
    x + 1
  end
end
