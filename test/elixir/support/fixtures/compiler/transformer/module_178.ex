# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module178 do
  def test do
    for <<a::4, (b::4 <- <<1, 2>>)>>, do: {a, b}
  end
end
