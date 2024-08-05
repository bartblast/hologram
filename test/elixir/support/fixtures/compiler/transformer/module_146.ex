# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module146 do
  # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
  def test(x) do
    try do
      x
    catch
      :error -> :a
    else
      y when is_integer(y) -> :b
    end
  end
end
