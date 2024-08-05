# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module132 do
  def test do
    # credo:disable-for-lines:5 Credo.Check.Readability.PreferImplicitTry
    try do
      1
    catch
      :exit, :timeout -> :error
    end
  end
end
