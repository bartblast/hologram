# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module106 do
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module106

  defstruct [:a, :b]

  def test(x) do
    %Module106{a: 1, b: 2} = x
  end
end
