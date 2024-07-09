# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module16 do
  def test do
    fn
      1 -> :ok
      2 -> :error
    end
  end
end
