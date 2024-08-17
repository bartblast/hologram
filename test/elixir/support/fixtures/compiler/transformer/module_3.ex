# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Tranformer.Module3 do
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  def data do
    iii = 123
    bbb = wrap_term("abc")
    fff = 1.23
    my_map = %{my_key: 123}

    [
      <<5.0>>,
      <<5>>,
      <<"abc">>,
      <<iii>>,
      <<Map.get(my_map, :my_key)>>,
      <<bbb::binary>>,
      <<bbb::bits>>,
      <<bbb::bitstring>>,
      <<bbb::bytes>>,
      <<fff::float>>,
      <<iii::integer>>,
      <<iii::utf8>>,
      <<iii::utf16>>,
      <<iii::utf32>>
    ]
  end
end
