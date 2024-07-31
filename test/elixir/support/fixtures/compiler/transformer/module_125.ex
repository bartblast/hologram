# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module125 do
  def test do
    1
  catch
    e -> {e, :ok}
  end
end
