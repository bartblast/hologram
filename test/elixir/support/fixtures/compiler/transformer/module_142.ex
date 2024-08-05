# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module142 do
  # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
  def test(x) do
    try do
      x
    catch
      :error -> :a
    else
      :b -> :c
    end
  end
end
