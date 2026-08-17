# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module182 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module182

  defstruct [:a, :b]

  def test(x) do
    case x do
      %Module182{a: a} -> a
    end
  end
end
