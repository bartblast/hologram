# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module168 do
  def test(y) do
    with :ok <- y do
    else
      msg when is_binary(msg) -> msg
    end
  end
end
