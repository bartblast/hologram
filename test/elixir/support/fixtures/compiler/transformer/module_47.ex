# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module47 do
  def test do
    for x <- [1, 2], my_filter_1(x), my_filter_2(x), do: x * x
  end

  defp my_filter_1(x) do
    x + 1
  end

  defp my_filter_2(x) do
    x + 2
  end
end
