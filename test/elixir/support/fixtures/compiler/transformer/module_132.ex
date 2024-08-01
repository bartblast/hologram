# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module132 do
  # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
  def test do
    try do
      1
    catch
      :exit, :timeout -> :error
    end
  end
end
