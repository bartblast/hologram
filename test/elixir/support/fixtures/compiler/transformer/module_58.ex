# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module58 do
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  def test do
    cond do
      wrap_term(1) -> :expr_1
      wrap_term(2) -> :expr_2
    end
  end
end
