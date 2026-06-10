# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module6 do
  def data do
    xyz = 123

    [
      <<xyz::signed>>,
      <<xyz::unsigned>>
    ]
  end
end
