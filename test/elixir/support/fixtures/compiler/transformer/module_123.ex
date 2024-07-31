# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module123 do
  def test do
    1
  rescue
    x in [ArgumentError] -> x
    y in [RuntimeError] -> y
  end
end
