# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module52 do
  def test do
    for x <- [1, 2], reduce: 0 do
      acc -> my_reducer(acc, x)
    end
  end

  defp my_reducer(acc, x) do
    acc + x
  end
end
