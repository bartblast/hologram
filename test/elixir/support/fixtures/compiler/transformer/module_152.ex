# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module152 do
  def test do
    # credo:disable-for-lines:6 Credo.Check.Readability.PreferImplicitTry
    try do
      1
    after
      x = 1
      x
    end
  end
end
