# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module53 do
  def test do
    for x <- [1, 2], reduce: {1, 9} do
      {1, a} -> my_reducer_1(a, x)
      {2, b} -> my_reducer_2(b, x)
    end
  end

  defp my_reducer_1(acc, x) do
    {2, acc + x}
  end

  defp my_reducer_2(acc, x) do
    {1, acc - x}
  end
end
