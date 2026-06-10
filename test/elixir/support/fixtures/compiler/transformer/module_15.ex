# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module15 do
  def test do
    &(&1 * &2 + &1)
  end
end
