# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module114 do
  def test do
    1
  rescue
    RuntimeError -> :ok
  end
end
