# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Refactor.WithClauses
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module162 do
  def test do
    with a = 1,
         b = 2 do
      {a, b}
    end
  end
end
