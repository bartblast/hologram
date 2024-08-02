# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module134 do
  # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
  def test do
    try do
      1
    catch
      :error, x when is_integer(x) -> :ok
    end
  end
end
