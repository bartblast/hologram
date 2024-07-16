# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module65 do
  @dialyzer {:no_improper_lists, test: 0}

  def test do
    [1 | [2 | 3]]
  end
end
