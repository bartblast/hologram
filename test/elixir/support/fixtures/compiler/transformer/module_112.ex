# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module112 do
  def test do
    try do
      1
    rescue
      [ArgumentError, RuntimeError] -> :ok
    end
  end
end
