# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module147 do
  def test(x) do
    x
  catch
    :error -> :a
  else
    y when is_integer(y) -> :b
  end
end
