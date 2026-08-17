# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module187 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module187

  defstruct [:a, :b]

  def test(x) do
    for %Module187{a: a} when is_integer(a) <- x, do: a
  end
end
