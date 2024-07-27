# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module109 do
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module109

  defstruct [:a, :b]

  def test(x) do
    %Module109{x | a: 1, b: 2}
  end
end
