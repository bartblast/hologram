# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module168 do
  def test(y) do
    with i when is_integer(i) <- y do
    else
      s when is_binary(s) ->
        {:error, :binary}
    end
  end
end
