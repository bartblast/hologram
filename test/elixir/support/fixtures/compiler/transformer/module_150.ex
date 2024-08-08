# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module150 do
  def test(x) do
    # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
    try do
      x
    catch
      :error -> :a
    else
      y when is_integer(y) when y > 1 when y < 9 -> :b
    end
  end
end
