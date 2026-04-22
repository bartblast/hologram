# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
# credo:disable-for-this-file Credo.Check.Refactor.WithClauses
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module173 do
  def test do
    with [do: 1],
         x = 1 do
      x
    end
  end
end
