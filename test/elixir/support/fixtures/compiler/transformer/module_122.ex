# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module122 do
  # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
  def test do
    try do
      1
    rescue
      x in [ArgumentError] -> {x, :ok}
      y in [RuntimeError] -> {y, :ok}
    end
  end
end
