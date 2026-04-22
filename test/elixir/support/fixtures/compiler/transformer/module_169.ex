# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module169 do
  def test(y) do
    with {:ok, _x} <- y do
    else
      {:error, msg} when is_binary(msg) ->
        msg

      {:error, code} when is_integer(code) ->
        code
    end
  end
end
