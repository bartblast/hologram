# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module183 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module183

  defstruct [:a, :b]

  def test(x) do
    case x do
      %Module183{a: a} when is_integer(a) -> a
    end
  end
end
