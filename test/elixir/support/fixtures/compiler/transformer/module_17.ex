# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module17 do
  def test do
    fn x when is_integer(x) -> x end
  end
end
