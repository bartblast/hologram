# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module151 do
  def test(x) do
    x
  catch
    :error -> :a
  else
    y when is_integer(y) when y > 1 when y < 9 -> :b
  end
end
