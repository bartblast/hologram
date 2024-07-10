# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module19 do
  def test do
    fn x when is_integer(x) when x > 1 when x < 9 -> x end
  end
end
