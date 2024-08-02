# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module135 do
  def test do
    1
  catch
    :error, x when is_integer(x) -> :ok
  end
end
