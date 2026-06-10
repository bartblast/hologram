# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module149 do
  def test(x) do
    x
  catch
    :error -> :a
  else
    y when is_integer(y) when y > 1 -> :b
  end
end
