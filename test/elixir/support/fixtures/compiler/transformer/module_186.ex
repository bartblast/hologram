# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module186 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module186

  defstruct [:a, :b]

  def test(x) do
    for %Module186{a: a} <- x, do: a
  end
end
