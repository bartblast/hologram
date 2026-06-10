# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module142 do
  def test(x) do
    # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
    try do
      x
    catch
      :error -> :a
    else
      :b -> :c
    end
  end
end
