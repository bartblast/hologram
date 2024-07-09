# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module18 do
  def test do
    fn x when is_integer(x) when x in [1, 2] -> x end
  end
end
