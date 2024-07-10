# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module18 do
  def test do
    fn x when is_integer(x) when x > 1 -> x end
  end
end
