# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module48 do
  def test do
    for x <- [1, 2], into: my_collectable(123), do: x * x
  end

  defp my_collectable(x) do
    [x]
  end
end
