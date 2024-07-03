# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module5 do
  def data do
    xyz = 123
    my_map = %{my_key: 123}

    [
      <<6>>,
      <<"my_str">>,
      <<xyz>>,
      <<Map.get(my_map, :my_key)>>,
      <<1, "", 2, "">>
    ]
  end
end
