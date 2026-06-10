# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module105 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module105

  defstruct [:a, :b]

  def test do
    %Module105{a: 1, b: 2}
  end
end
