# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module122 do
  def test do
    # credo:disable-for-lines:6 Credo.Check.Readability.PreferImplicitTry
    try do
      1
    rescue
      x in [ArgumentError] -> {x, :ok}
      y in [RuntimeError] -> {y, :ok}
    end
  end
end
