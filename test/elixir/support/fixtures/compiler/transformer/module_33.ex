# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module33 do
  alias Hologram.Test.Fixtures.Compiler.Tranformer.Module32

  def test do
    &Module32.my_fun(&1, 2, [3, &2])
  end
end
