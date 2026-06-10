# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module119 do
  def test do
    1
  rescue
    e in [RuntimeError] -> {e, :ok}
  end
end
