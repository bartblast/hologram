# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module145 do
  def test(x) do
    x
  catch
    :error -> :a
  else
    :b -> :c
    :d -> :e
  end
end
