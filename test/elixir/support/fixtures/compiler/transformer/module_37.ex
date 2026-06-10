# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module37 do
  def test(x) do
    case x do
      {:ok, n} when is_integer(n) -> n
    end
  end
end
