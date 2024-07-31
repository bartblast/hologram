# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module120 do
  # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
  def test do
    try do
      1
    rescue
      e in [ArgumentError, RuntimeError] -> {e, :ok}
    end
  end
end
