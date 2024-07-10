# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module20 do
  def test do
    fn %x{} -> x end
  end
end
