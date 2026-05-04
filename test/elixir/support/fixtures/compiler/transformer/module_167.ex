# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module167 do
  def test(y) do
    with :ok <- y do
    else
      :error -> 0
      :timeout -> 1
    end
  end
end
