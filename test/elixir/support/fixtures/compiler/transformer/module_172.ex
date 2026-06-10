# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module172 do
  def test(y) do
    key = :error

    with :ok <- y do
    else
      ^key -> :error
    end
  end
end
