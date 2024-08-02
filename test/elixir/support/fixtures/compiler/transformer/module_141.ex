# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module141 do
  def test do
    1
  catch
    :error -> :a
    :warning -> :b
  end
end
