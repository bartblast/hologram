# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module129 do
  def test do
    1
  catch
    x when is_integer(x) when x > 1 -> :ok
  end
end
