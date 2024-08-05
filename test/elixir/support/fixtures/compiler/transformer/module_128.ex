# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module128 do
  def test do
    # credo:disable-for-lines:5 Credo.Check.Readability.PreferImplicitTry
    try do
      1
    catch
      x when is_integer(x) when x > 1 -> :ok
    end
  end
end
