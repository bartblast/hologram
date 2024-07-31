# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module115 do
  def test do
    1
  rescue
    [ArgumentError, RuntimeError] -> :ok
  end
end
