# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module21 do
  def test do
    fn %x{} when x != MyModule -> x end
  end
end
