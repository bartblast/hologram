# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module86 do
  def test do
    %{a: x, b: y} = %{a: 1, b: 2}
    {x, y}
  end
end
