# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module166 do
  def test(x) do
    with :ok <- x do
    else
      _i ->
        {:error, :not_ok}
    end
  end
end
