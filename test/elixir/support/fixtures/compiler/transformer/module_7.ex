# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module7 do
  def data do
    xyz = 123

    [
      <<xyz::big>>,
      <<xyz::little>>,
      <<xyz::native>>
    ]
  end
end
