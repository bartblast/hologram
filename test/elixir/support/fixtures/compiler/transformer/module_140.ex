# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module140 do
  def test do
    # credo:disable-for-lines:6 Credo.Check.Readability.PreferImplicitTry
    try do
      1
    catch
      :error -> :a
      :warning -> :b
    end
  end
end
