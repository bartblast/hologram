# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module110 do
  def test do
    # credo:disable-for-lines:6 Credo.Check.Readability.PreferImplicitTry
    try do
      x = 1
      x
    rescue
      e -> {e, :ok}
    end
  end
end
