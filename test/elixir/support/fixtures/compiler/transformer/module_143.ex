# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module143 do
  def test(x) do
    x
  catch
    :error -> :a
  else
    :b -> :c
  end
end
