# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module2 do
  def data do
    xyz = 123

    [
      <<xyz::size(3)>>,
      <<xyz::3>>,
      <<xyz::3*5>>
    ]
  end
end
