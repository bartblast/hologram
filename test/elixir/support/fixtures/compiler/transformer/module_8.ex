# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module8 do
  def data do
    [
      <<>>,
      <<987>>,
      <<987, 876>>,
      <<333, <<444, 555, 666>>, 777>>
    ]
  end
end
