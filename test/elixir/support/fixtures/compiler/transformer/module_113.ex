# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module113 do
  def test do
    x = 1
    x
  rescue
    e -> {e, :ok}
  end
end
