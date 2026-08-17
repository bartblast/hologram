# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module185 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module185

  defstruct [:a, :b]

  def test do
    for x <- [1, 2], reduce: %Module185{a: 0, b: nil} do
      %Module185{a: a} -> my_reducer(a, x)
    end
  end

  defp my_reducer(a, x) do
    %Module185{a: a + x, b: nil}
  end
end
