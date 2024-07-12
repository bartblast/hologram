# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module38 do
  def test(x) do
    case x do
      {:ok, n} when is_integer(n) when n > 1 -> n
    end
  end
end
