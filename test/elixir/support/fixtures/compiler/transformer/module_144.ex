# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module144 do
  def test(x) do
    # credo:disable-for-lines:8 Credo.Check.Readability.PreferImplicitTry
    try do
      x
    catch
      :error -> :a
    else
      :b -> :c
      :d -> :e
    end
  end
end
